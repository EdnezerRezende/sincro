import { Injectable } from '@nestjs/common';
import { google } from 'googleapis';
import { GmailOAuthService } from '../gmail/gmail-oauth.service';

export interface CriarEventoParams {
  tituloCompromisso: string;
  dataHoraLimite: string; // ISO 8601, idealmente com offset explícito (ex.: 2026-09-01T15:00:00-03:00)
  antecedenciaMinutos: number;
}

const DURACAO_EVENTO_MINUTOS = 30;

/** Separa "hora de parede" e offset de uma string ISO 8601. O offset é opcional: clientes antigos
 *  ainda podem mandar uma data ingênua. */
const ISO_8601 = /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?(?:\.\d+)?)(Z|[+-]\d{2}:\d{2})?$/;

@Injectable()
export class CalendarApiClient {
  constructor(private readonly oauthService: GmailOAuthService) {}

  /** Creates a real event on the user's primary calendar with two reminders — Google Calendar
   *  itself delivers these notifications; this app has no scheduling mechanism of its own.
   *
   *  `dataHoraLimite` chega com o offset do dispositivo do usuário e é repassado INTACTO para o
   *  campo `dateTime` do Google (RFC3339 com offset dispensa o campo `timeZone`). Converter a
   *  string para `Date` e reserializar com `toISOString()` era justamente o passo que perdia o
   *  fuso do usuário: uma data ingênua era resolvida no fuso do SERVIDOR, congelando o instante
   *  errado (um "15h" brasileiro virava 12h BRT em servidor UTC). */
  async criarEvento(refreshToken: string, params: CriarEventoParams): Promise<void> {
    const auth = this.oauthService.authenticatedClientFor(refreshToken);
    const calendar = google.calendar({ version: 'v3', auth });
    const inicio = this.comOffsetExplicito(params.dataHoraLimite);
    const fim = this.somarMinutosPreservandoOffset(inicio, DURACAO_EVENTO_MINUTOS);

    await calendar.events.insert({
      calendarId: 'primary',
      requestBody: {
        summary: params.tituloCompromisso,
        start: { dateTime: inicio },
        end: { dateTime: fim },
        // `overrides` é sempre relativo ao início do evento, calculado pelo próprio Google — como
        // `start` preserva o fuso original, os lembretes caem no horário certo para o usuário.
        reminders: {
          useDefault: false,
          overrides: [
            { method: 'popup', minutes: params.antecedenciaMinutos },
            { method: 'popup', minutes: 30 },
          ],
        },
      },
    });
  }

  /** O Google recusa um `dateTime` sem offset quando não há um `timeZone` junto. Se um cliente
   *  antigo mandar uma data ingênua, ela é resolvida no fuso do servidor (comportamento antigo,
   *  impreciso porém válido) só para o pedido não falhar. */
  private comOffsetExplicito(iso: string): string {
    const valor = iso.trim();
    const partes = ISO_8601.exec(valor);
    if (partes && partes[2]) return valor;
    return new Date(valor).toISOString();
  }

  /** Soma minutos à hora de parede e reanexa o MESMO offset, em vez de passar por um instante UTC
   *  intermediário que reescreveria o fuso do usuário. */
  private somarMinutosPreservandoOffset(iso: string, minutos: number): string {
    const partes = ISO_8601.exec(iso);
    if (!partes) {
      return new Date(new Date(iso).getTime() + minutos * 60_000).toISOString();
    }
    const [, horaDeParede, offset] = partes;
    const deslocada = new Date(new Date(`${horaDeParede}Z`).getTime() + minutos * 60_000);
    return `${deslocada.toISOString().slice(0, 19)}${offset ?? ''}`;
  }
}
