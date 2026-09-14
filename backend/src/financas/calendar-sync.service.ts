import { Injectable, Logger } from '@nestjs/common';
import { CalendarApiClient } from '../calendar/calendar-api-client.service';
import { GmailConnectionsService } from '../gmail/gmail-connections.service';

interface LancamentoParaCalendar {
  id: string;
  descricao: string;
  instituicao: string | null;
  valor: unknown;
  dataVencimento: Date;
  googleEventId: string | null;
}

@Injectable()
export class FinanceCalendarSyncService {
  private readonly logger = new Logger(FinanceCalendarSyncService.name);

  constructor(
    private readonly calendarApiClient: CalendarApiClient,
    private readonly gmailConnectionsService: GmailConnectionsService,
  ) {}

  async syncOnConfirm(userId: string, lancamento: LancamentoParaCalendar): Promise<string | null> {
    try {
      const refreshToken = await this.gmailConnectionsService.getDecryptedRefreshToken(userId);
      if (!refreshToken) return null;

      const titulo = lancamento.instituicao
        ? `Pagar: ${lancamento.instituicao} · ${lancamento.descricao}`
        : `Pagar: ${lancamento.descricao}`;
      const valorNumero = this.toNumberOrNull(lancamento.valor);
      const dataIso = lancamento.dataVencimento.toISOString().slice(0, 10);
      const params = {
        titulo,
        descricao: valorNumero !== null ? `Valor: R$ ${valorNumero.toFixed(2)}` : '',
        dataHoraInicio: dataIso,
        dataHoraFim: dataIso,
        ehDiaInteiro: true,
        lembretesMinutosAntes: [24 * 60],
        categoria: 'FINANCEIRO' as const,
        lancamentoId: lancamento.id,
      };

      if (lancamento.googleEventId) {
        await this.calendarApiClient.atualizarEvento(refreshToken, lancamento.googleEventId, params);
        return lancamento.googleEventId;
      }
      const evento = await this.calendarApiClient.criarEventoCompleto(refreshToken, params);
      return evento.id;
    } catch (error) {
      this.logger.warn(`Calendar sync failed for lançamento ${lancamento.id}: ${(error as Error).message}`);
      return null;
    }
  }

  /** Retorna `true` quando o fim confirmado é "evento não existe mais no Google Calendar" —
   *  inclui o caso de a exclusão de fato ter ocorrido e o caso de o evento já não existir mais
   *  lá (Google responde 404/410 para excluir um evento inexistente, o que já é o estado
   *  desejado). Retorna `false` quando isso NÃO pôde ser confirmado: sem conexão Gmail, ou a
   *  chamada à API falhou por outro motivo (rede, token revogado, erro 5xx do Google) — nesses
   *  casos o chamador deve manter `googleEventId` para tentar de novo depois, em vez de perder a
   *  única referência ao evento que pode continuar existindo. */
  async removeEvent(userId: string, googleEventId: string | null): Promise<boolean> {
    if (!googleEventId) return true;
    try {
      const refreshToken = await this.gmailConnectionsService.getDecryptedRefreshToken(userId);
      if (!refreshToken) return false;
      await this.calendarApiClient.deletarEvento(refreshToken, googleEventId);
      return true;
    } catch (error) {
      if (this.isEventoJaInexistente(error)) return true;
      this.logger.warn(`Calendar event deletion failed for event ${googleEventId}: ${(error as Error).message}`);
      return false;
    }
  }

  /** Erros do pacote `googleapis` normalmente carregam o status HTTP em `error.code` ou
   *  `error.response.status`. 404/410 significam que o evento já não existe no Google Calendar —
   *  o estado final desejado já vale, então não é uma falha real de remoção. */
  private isEventoJaInexistente(error: unknown): boolean {
    const bruto = (error as { code?: unknown; response?: { status?: unknown } })?.code
      ?? (error as { response?: { status?: unknown } })?.response?.status;
    const status = typeof bruto === 'string' ? Number(bruto) : bruto;
    return status === 404 || status === 410;
  }

  private toNumberOrNull(value: unknown): number | null {
    if (value === null || value === undefined) return null;
    if (typeof value === 'number') return value;
    const withToNumber = value as { toNumber?: () => number };
    return typeof withToNumber.toNumber === 'function' ? withToNumber.toNumber() : Number(value);
  }
}
