import { Injectable } from '@nestjs/common';
import { google } from 'googleapis';
import { GmailOAuthService } from '../gmail/gmail-oauth.service';

export interface CriarEventoParams {
  tituloCompromisso: string;
  dataHoraLimite: string; // ISO
  antecedenciaMinutos: number;
}

@Injectable()
export class CalendarApiClient {
  constructor(private readonly oauthService: GmailOAuthService) {}

  /** Creates a real event on the user's primary calendar with two reminders — Google Calendar
   *  itself delivers these notifications; this app has no scheduling mechanism of its own. */
  async criarEvento(refreshToken: string, params: CriarEventoParams): Promise<void> {
    const auth = this.oauthService.authenticatedClientFor(refreshToken);
    const calendar = google.calendar({ version: 'v3', auth });
    const inicio = new Date(params.dataHoraLimite);
    const fim = new Date(inicio.getTime() + 30 * 60 * 1000);

    await calendar.events.insert({
      calendarId: 'primary',
      requestBody: {
        summary: params.tituloCompromisso,
        start: { dateTime: inicio.toISOString() },
        end: { dateTime: fim.toISOString() },
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
}
