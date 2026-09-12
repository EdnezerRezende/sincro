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

  async removeEvent(userId: string, googleEventId: string | null): Promise<void> {
    if (!googleEventId) return;
    try {
      const refreshToken = await this.gmailConnectionsService.getDecryptedRefreshToken(userId);
      if (!refreshToken) return;
      await this.calendarApiClient.deletarEvento(refreshToken, googleEventId);
    } catch (error) {
      this.logger.warn(`Calendar event deletion failed for event ${googleEventId}: ${(error as Error).message}`);
    }
  }

  private toNumberOrNull(value: unknown): number | null {
    if (value === null || value === undefined) return null;
    if (typeof value === 'number') return value;
    const withToNumber = value as { toNumber?: () => number };
    return typeof withToNumber.toNumber === 'function' ? withToNumber.toNumber() : Number(value);
  }
}
