import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { FinanceCalendarSyncService } from './calendar-sync.service';
import { ConfirmarLancamentoDto } from './dto/confirmar-lancamento.dto';
import { CreateLancamentoDto } from './dto/create-lancamento.dto';
import { UpdateLancamentoDto } from './dto/update-lancamento.dto';

const TIPOS_ELEGIVEIS_PARA_AGENDA = ['DESPESA', 'FATURA_CARTAO'];

/** Superset dos campos que `sincronizarCalendarioParaResultado` precisa: `tipo`/`status`/`isPago`
 *  para a decisão de criar/remover, e o restante (`descricao`, `instituicao`, `valor`,
 *  `dataVencimento`) porque é exatamente o que `FinanceCalendarSyncService.syncOnConfirm` espera
 *  (`LancamentoParaCalendar` em `calendar-sync.service.ts`) — mantendo os dois em sincronia evita
 *  um cast manual ao repassar `resultado` para `syncOnConfirm`. */
interface LancamentoParaSincCalendario {
  id: string;
  tipo: string;
  status: string;
  isPago: boolean;
  googleEventId: string | null;
  descricao: string;
  instituicao: string | null;
  valor: unknown;
  dataVencimento: Date;
}

@Injectable()
export class LancamentosService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly calendarSync: FinanceCalendarSyncService,
  ) {}

  list(userId: string, filtros: { status?: string; mes?: string }) {
    const where: Record<string, unknown> = { userId };
    if (filtros.status) where.status = filtros.status;
    if (filtros.mes) {
      const [ano, mes] = filtros.mes.split('-').map(Number);
      where.dataVencimento = {
        gte: new Date(Date.UTC(ano, mes - 1, 1)),
        lt: new Date(Date.UTC(ano, mes, 1)),
      };
    }
    return this.prisma.lancamentoFinanceiro.findMany({ where, orderBy: { dataVencimento: 'asc' } });
  }

  async createManual(userId: string, dto: CreateLancamentoDto) {
    await this.assertContaECartaoPertencemAoUsuario(userId, dto.contaId, dto.cartaoId);
    const dataVencimento = new Date(dto.dataVencimento);
    const dataCompetencia = dto.dataCompetencia ? new Date(dto.dataCompetencia) : dataVencimento;
    const criado = await this.prisma.lancamentoFinanceiro.create({
      data: {
        userId,
        tipo: dto.tipo,
        descricao: dto.descricao,
        instituicao: dto.instituicao,
        valor: dto.valor,
        dataVencimento,
        dataCompetencia,
        status: 'CONFIRMADO',
        origem: 'MANUAL',
        contaId: dto.contaId,
        cartaoId: dto.cartaoId,
        isPago: dto.isPago ?? false,
      },
    });
    await this.sincronizarCalendarioParaResultado(userId, criado);
    return criado;
  }

  async update(userId: string, id: string, dto: UpdateLancamentoDto) {
    await this.getOwnedOrThrow(userId, id); // garante posse; o resultado não é mais lido — a decisão de calendário usa `atualizado`, não o estado anterior
    await this.assertContaECartaoPertencemAoUsuario(userId, dto.contaId, dto.cartaoId);
    const data: Record<string, unknown> = { ...dto };
    if (dto.dataVencimento) data.dataVencimento = new Date(dto.dataVencimento);
    if (dto.dataCompetencia) data.dataCompetencia = new Date(dto.dataCompetencia);

    const atualizado = await this.prisma.lancamentoFinanceiro.update({ where: { id }, data });
    await this.sincronizarCalendarioParaResultado(userId, atualizado);
    return atualizado;
  }

  async confirmar(userId: string, id: string, dto: ConfirmarLancamentoDto) {
    await this.getOwnedOrThrow(userId, id);
    await this.assertContaECartaoPertencemAoUsuario(userId, dto.contaId, dto.cartaoId);
    const data: Record<string, unknown> = { status: 'CONFIRMADO' };
    if (dto.valor !== undefined) data.valor = dto.valor;
    if (dto.dataVencimento) data.dataVencimento = new Date(dto.dataVencimento);
    if (dto.contaId !== undefined) data.contaId = dto.contaId;
    if (dto.cartaoId !== undefined) data.cartaoId = dto.cartaoId;

    const atualizado = await this.prisma.lancamentoFinanceiro.update({ where: { id }, data });
    await this.sincronizarCalendarioParaResultado(userId, atualizado);
    return atualizado;
  }

  async ignorar(userId: string, id: string) {
    const lancamento = await this.getOwnedOrThrow(userId, id);
    const atualizado = await this.prisma.lancamentoFinanceiro.update({
      where: { id },
      data: { status: 'IGNORADO' },
    });
    await this.calendarSync.removeEvent(userId, lancamento.googleEventId);
    return atualizado;
  }

  async remove(userId: string, id: string): Promise<void> {
    const lancamento = await this.getOwnedOrThrow(userId, id);
    await this.prisma.lancamentoFinanceiro.delete({ where: { id } });
    await this.calendarSync.removeEvent(userId, lancamento.googleEventId);
  }

  /** Único ponto de decisão de calendário para o resultado de uma escrita em
   *  `LancamentoFinanceiro` (`createManual`, `update`, `confirmar`) — evita que as três
   *  chamadas divirjam sobre quando um evento deve existir. Regra: só lançamento CONFIRMADO
   *  de tipo DESPESA/FATURA_CARTAO tem evento; se `isPago` for true, o evento (se houver) é
   *  removido em vez de sincronizado. `ignorar`/`remove` continuam removendo incondicionalmente
   *  fora deste método, pois ali o lançamento deixa de existir/valer independente de tipo. */
  private async sincronizarCalendarioParaResultado(
    userId: string,
    resultado: LancamentoParaSincCalendario,
  ): Promise<void> {
    if (resultado.status !== 'CONFIRMADO') return;

    if (resultado.isPago) {
      if (!resultado.googleEventId) return;
      await this.calendarSync.removeEvent(userId, resultado.googleEventId);
      await this.prisma.lancamentoFinanceiro.update({
        where: { id: resultado.id },
        data: { googleEventId: null },
      });
      return;
    }

    if (!TIPOS_ELEGIVEIS_PARA_AGENDA.includes(resultado.tipo)) return;

    const googleEventId = await this.calendarSync.syncOnConfirm(userId, resultado);
    if (googleEventId) {
      await this.prisma.lancamentoFinanceiro.update({
        where: { id: resultado.id },
        data: { googleEventId },
      });
    }
  }

  protected async getOwnedOrThrow(userId: string, id: string) {
    const lancamento = await this.prisma.lancamentoFinanceiro.findFirst({ where: { id, userId } });
    if (!lancamento) throw new NotFoundException('Lançamento não encontrado');
    return lancamento;
  }

  private async assertContaECartaoPertencemAoUsuario(
    userId: string,
    contaId: string | undefined,
    cartaoId: string | undefined,
  ) {
    if (contaId) {
      const conta = await this.prisma.contaFinanceira.findFirst({ where: { id: contaId, userId } });
      if (!conta) throw new NotFoundException('Conta não encontrada');
    }
    if (cartaoId) {
      const cartao = await this.prisma.cartaoCredito.findFirst({ where: { id: cartaoId, userId } });
      if (!cartao) throw new NotFoundException('Cartão não encontrado');
    }
  }
}
