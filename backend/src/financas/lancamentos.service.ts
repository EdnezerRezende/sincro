import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { FinanceCalendarSyncService } from './calendar-sync.service';
import { CreateLancamentoDto } from './dto/create-lancamento.dto';
import { UpdateLancamentoDto } from './dto/update-lancamento.dto';

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

  createManual(userId: string, dto: CreateLancamentoDto) {
    const dataVencimento = new Date(dto.dataVencimento);
    const dataCompetencia = dto.dataCompetencia ? new Date(dto.dataCompetencia) : dataVencimento;
    return this.prisma.lancamentoFinanceiro.create({
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
  }

  async update(userId: string, id: string, dto: UpdateLancamentoDto) {
    const lancamento = await this.getOwnedOrThrow(userId, id);
    const data: Record<string, unknown> = { ...dto };
    if (dto.dataVencimento) data.dataVencimento = new Date(dto.dataVencimento);
    if (dto.dataCompetencia) data.dataCompetencia = new Date(dto.dataCompetencia);

    const atualizado = await this.prisma.lancamentoFinanceiro.update({ where: { id }, data });

    if (lancamento.status === 'CONFIRMADO' && atualizado.status === 'CONFIRMADO') {
      const googleEventId = await this.calendarSync.syncOnConfirm(userId, atualizado);
      if (googleEventId) {
        await this.prisma.lancamentoFinanceiro.update({ where: { id }, data: { googleEventId } });
      }
    }
    return atualizado;
  }

  protected async getOwnedOrThrow(userId: string, id: string) {
    const lancamento = await this.prisma.lancamentoFinanceiro.findFirst({ where: { id, userId } });
    if (!lancamento) throw new NotFoundException('Lançamento não encontrado');
    return lancamento;
  }
}
