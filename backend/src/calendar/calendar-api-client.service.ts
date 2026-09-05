import { Injectable } from '@nestjs/common';
import { google, calendar_v3 } from 'googleapis';
import { GmailOAuthService } from '../gmail/gmail-oauth.service';

export interface CriarEventoParams {
  tituloCompromisso: string;
  dataHoraLimite: string; // ISO 8601, idealmente com offset explícito (ex.: 2026-09-01T15:00:00-03:00)
  antecedenciaMinutos: number;
}

/** Shape geral de um evento de agenda exposto ao app mobile — distinto de `CriarEventoParams`,
 *  que é específico do fluxo de compromisso sugerido por e-mail. */
export interface EventoCalendario {
  id: string;
  titulo: string;
  descricao: string;
  dataHoraInicio: string;
  dataHoraFim: string;
  ehDiaInteiro: boolean; // true se o evento é um evento de dia inteiro (all-day)
}

/** Parâmetros para criar/atualizar um evento completo (agenda sempre-editável do usuário),
 *  diferente de `CriarEventoParams` (duração fixa de 30min, lembretes fixos, usado só pelo fluxo
 *  de confirmação de compromisso sugerido). */
export interface EventoCompletoParams {
  titulo: string;
  descricao: string;
  dataHoraInicio: string;
  dataHoraFim: string;
  ehDiaInteiro?: boolean; // true se o evento é um evento de dia inteiro (all-day)
}

const DURACAO_EVENTO_MINUTOS = 30;

/** Separa "hora de parede" e offset de uma string ISO 8601. O offset é opcional: clientes antigos
 *  ainda podem mandar uma data ingênua. */
const ISO_8601 =
  /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?(?:\.\d+)?)(Z|[+-]\d{2}:\d{2})?$/;

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
  async criarEvento(
    refreshToken: string,
    params: CriarEventoParams,
  ): Promise<void> {
    const auth = this.oauthService.authenticatedClientFor(refreshToken);
    const calendar = google.calendar({ version: 'v3', auth });
    const inicio = this.comOffsetExplicito(params.dataHoraLimite);
    const fim = this.somarMinutosPreservandoOffset(
      inicio,
      DURACAO_EVENTO_MINUTOS,
    );

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

  /** Lista eventos do calendário principal do usuário no intervalo [timeMin, timeMax). Usado
   *  tanto para "próximos eventos" quanto para a visão mensal — a diferença é só o intervalo que
   *  o controller calcula e passa para cá. */
  async listarEventos(
    refreshToken: string,
    timeMin: string,
    timeMax: string,
  ): Promise<EventoCalendario[]> {
    const auth = this.oauthService.authenticatedClientFor(refreshToken);
    const calendar = google.calendar({ version: 'v3', auth });
    const { data } = await calendar.events.list({
      calendarId: 'primary',
      timeMin,
      timeMax,
      singleEvents: true,
      orderBy: 'startTime',
    });
    return (data.items ?? []).map((item) => this.paraEventoCalendario(item));
  }

  /** Cria um evento completo e de propósito geral (agenda sempre-editável do usuário) — distinto
   *  de `criarEvento`, que é fixo em 30min e usado apenas pelo fluxo de confirmação de compromisso
   *  sugerido a partir de um e-mail. Preserva o offset do usuário do mesmo jeito que `criarEvento`
   *  (ver comentário acima) para não repetir o bug de reescrever o fuso no servidor.
   *
   *  Se `ehDiaInteiro` é true, o evento é tratado como um evento de dia inteiro (all-day):
   *  usa o campo `date` (YYYY-MM-DD) em vez de `dateTime`, preservando o status all-day no
   *  Google Calendar e evitando corrupção silenciosa ao editar. */
  async criarEventoCompleto(
    refreshToken: string,
    params: EventoCompletoParams,
  ): Promise<EventoCalendario> {
    const auth = this.oauthService.authenticatedClientFor(refreshToken);
    const calendar = google.calendar({ version: 'v3', auth });

    if (params.ehDiaInteiro) {
      // Evento de dia inteiro: usa `date` em vez de `dateTime`
      const dataInicio = this.extrairData(params.dataHoraInicio);
      const dataFim = this.extrairData(params.dataHoraFim);
      const { data } = await calendar.events.insert({
        calendarId: 'primary',
        requestBody: {
          summary: params.titulo,
          description: params.descricao,
          start: { date: dataInicio },
          end: { date: dataFim },
        },
      });
      return this.paraEventoCalendario(data);
    }

    // Evento com hora: usa `dateTime` com offset preservado
    const inicio = this.comOffsetExplicito(params.dataHoraInicio);
    const fim = this.comOffsetExplicito(params.dataHoraFim);
    const { data } = await calendar.events.insert({
      calendarId: 'primary',
      requestBody: {
        summary: params.titulo,
        description: params.descricao,
        start: { dateTime: inicio },
        end: { dateTime: fim },
      },
    });
    return this.paraEventoCalendario(data);
  }

  /** Atualiza um evento existente. Mesmo cuidado de preservação de offset que `criarEventoCompleto`.
   *
   *  Usa `events.patch`, não `events.update`: o `update` do Google Calendar NÃO segue semântica de
   *  patch — ele substitui o recurso do evento inteiro pelo `requestBody` enviado, apagando
   *  attendees/reminders/location/recurrence que não foram incluídos aqui. `patch` só altera os
   *  campos presentes no corpo, preservando o resto do evento real do usuário.
   *
   *  Se `ehDiaInteiro` é true, preserva o status de evento de dia inteiro (all-day) ao editar:
   *  envia `date` em vez de `dateTime`, evitando corrupção silenciosa em eventos all-day. */
  async atualizarEvento(
    refreshToken: string,
    eventId: string,
    params: EventoCompletoParams,
  ): Promise<EventoCalendario> {
    const auth = this.oauthService.authenticatedClientFor(refreshToken);
    const calendar = google.calendar({ version: 'v3', auth });

    if (params.ehDiaInteiro) {
      // Evento de dia inteiro: usa `date` em vez de `dateTime`
      const dataInicio = this.extrairData(params.dataHoraInicio);
      const dataFim = this.extrairData(params.dataHoraFim);
      const { data } = await calendar.events.patch({
        calendarId: 'primary',
        eventId,
        requestBody: {
          summary: params.titulo,
          description: params.descricao,
          start: { date: dataInicio },
          end: { date: dataFim },
        },
      });
      return this.paraEventoCalendario(data);
    }

    // Evento com hora: usa `dateTime` com offset preservado
    const inicio = this.comOffsetExplicito(params.dataHoraInicio);
    const fim = this.comOffsetExplicito(params.dataHoraFim);
    const { data } = await calendar.events.patch({
      calendarId: 'primary',
      eventId,
      requestBody: {
        summary: params.titulo,
        description: params.descricao,
        start: { dateTime: inicio },
        end: { dateTime: fim },
      },
    });
    return this.paraEventoCalendario(data);
  }

  async deletarEvento(refreshToken: string, eventId: string): Promise<void> {
    const auth = this.oauthService.authenticatedClientFor(refreshToken);
    const calendar = google.calendar({ version: 'v3', auth });
    await calendar.events.delete({ calendarId: 'primary', eventId });
  }

  private paraEventoCalendario(
    item: calendar_v3.Schema$Event,
  ): EventoCalendario {
    // Determina se é um evento de dia inteiro (all-day): Google Calendar usa `date` em vez de
    // `dateTime` para esses eventos. A presença de `start.date` (sem `start.dateTime`) indica
    // um evento all-day. Essencial para a mobile app não corromper all-day events ao editá-los.
    const ehDiaInteiro = !item.start?.dateTime && !!item.start?.date;
    return {
      id: item.id ?? '',
      titulo: item.summary ?? '',
      descricao: item.description ?? '',
      dataHoraInicio: item.start?.dateTime ?? item.start?.date ?? '',
      dataHoraFim: item.end?.dateTime ?? item.end?.date ?? '',
      ehDiaInteiro,
    };
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
    const deslocada = new Date(
      new Date(`${horaDeParede}Z`).getTime() + minutos * 60_000,
    );
    return `${deslocada.toISOString().slice(0, 19)}${offset ?? ''}`;
  }

  /** Extrai a parte de data (YYYY-MM-DD) de uma string ISO 8601, descartando hora e offset.
   *  Usado para eventos de dia inteiro (all-day) que devem ser salvos no Google Calendar com
   *  o campo `date` (não `dateTime`). */
  private extrairData(iso: string): string {
    // Se já é um `date` (YYYY-MM-DD), retorna como está
    if (/^\d{4}-\d{2}-\d{2}$/.test(iso)) {
      return iso;
    }
    // Caso contrário, extrai a data de um string `dateTime`
    const partes = ISO_8601.exec(iso.trim());
    if (!partes) {
      // Fallback: converte para Date e extrai a data em UTC
      const dt = new Date(iso);
      return dt.toISOString().slice(0, 10);
    }
    // partes[1] é a hora de parede (YYYY-MM-DDTHH:mm:ss...); pega apenas YYYY-MM-DD
    return partes[1].slice(0, 10);
  }
}
