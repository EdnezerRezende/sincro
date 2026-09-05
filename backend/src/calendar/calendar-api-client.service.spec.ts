import { CalendarApiClient } from './calendar-api-client.service';

jest.mock('googleapis', () => {
  const insert = jest.fn().mockResolvedValue({ data: {} });
  const list = jest.fn().mockResolvedValue({ data: { items: [] } });
  const patch = jest.fn().mockResolvedValue({ data: {} });
  const del = jest.fn().mockResolvedValue({ data: {} });
  return {
    google: {
      calendar: jest.fn(() => ({
        events: { insert, list, patch, delete: del },
      })),
    },
    __insert: insert,
    __list: list,
    __patch: patch,
    __delete: del,
  };
});

function buildClient() {
  const oauthService = { authenticatedClientFor: jest.fn(() => ({ fake: 'auth' })) };
  return new CalendarApiClient(oauthService as never);
}

function corpoEnviado() {
  const { __insert } = jest.requireMock('googleapis');
  return __insert.mock.calls[0][0].requestBody;
}

function mocksGoogleapis() {
  return jest.requireMock('googleapis') as {
    __insert: jest.Mock;
    __list: jest.Mock;
    __patch: jest.Mock;
    __delete: jest.Mock;
  };
}

describe('CalendarApiClient.criarEvento', () => {
  beforeEach(() => {
    const { __insert, __list, __patch, __delete } = mocksGoogleapis();
    __insert.mockClear().mockResolvedValue({ data: {} });
    __list.mockClear().mockResolvedValue({ data: { items: [] } });
    __patch.mockClear().mockResolvedValue({ data: {} });
    __delete.mockClear().mockResolvedValue({ data: {} });
  });

  it('repassa o offset do usuário intacto para start/end, sem convertê-lo para outro fuso', async () => {
    await buildClient().criarEvento('rt-123', {
      tituloCompromisso: 'Enviar relatório',
      dataHoraLimite: '2026-09-01T15:00:00-03:00',
      antecedenciaMinutos: 1440,
    });

    const body = corpoEnviado();
    expect(body.start.dateTime).toBe('2026-09-01T15:00:00-03:00');
    expect(body.end.dateTime).toBe('2026-09-01T15:30:00-03:00');
  });

  it('preserva um offset de meia hora e a virada de dia ao somar a duração', async () => {
    await buildClient().criarEvento('rt-123', {
      tituloCompromisso: 'Ligar para o cliente',
      dataHoraLimite: '2026-09-01T23:50:00.000+05:30',
      antecedenciaMinutos: 60,
    });

    const body = corpoEnviado();
    expect(body.start.dateTime).toBe('2026-09-01T23:50:00.000+05:30');
    expect(body.end.dateTime).toBe('2026-09-02T00:20:00+05:30');
  });

  it('mantém o sufixo Z quando o horário já vem em UTC', async () => {
    await buildClient().criarEvento('rt-123', {
      tituloCompromisso: 'Reunião',
      dataHoraLimite: '2026-09-01T18:00:00Z',
      antecedenciaMinutos: 60,
    });

    const body = corpoEnviado();
    expect(body.start.dateTime).toBe('2026-09-01T18:00:00Z');
    expect(body.end.dateTime).toBe('2026-09-01T18:30:00Z');
  });

  it('ainda produz um RFC3339 válido quando a data chega ingênua (cliente antigo)', async () => {
    await buildClient().criarEvento('rt-123', {
      tituloCompromisso: 'Reunião',
      dataHoraLimite: '2026-09-01T18:00:00',
      antecedenciaMinutos: 60,
    });

    const body = corpoEnviado();
    expect(body.start.dateTime).toMatch(/(Z|[+-]\d{2}:\d{2})$/);
    expect(body.end.dateTime).toMatch(/(Z|[+-]\d{2}:\d{2})$/);
    expect(new Date(body.end.dateTime).getTime() - new Date(body.start.dateTime).getTime()).toBe(
      30 * 60 * 1000,
    );
  });

  it('registra os dois lembretes relativos ao início do evento', async () => {
    await buildClient().criarEvento('rt-123', {
      tituloCompromisso: 'Enviar relatório',
      dataHoraLimite: '2026-09-01T15:00:00-03:00',
      antecedenciaMinutos: 1440,
    });

    const body = corpoEnviado();
    expect(body.summary).toBe('Enviar relatório');
    expect(body.reminders).toEqual({
      useDefault: false,
      overrides: [
        { method: 'popup', minutes: 1440 },
        { method: 'popup', minutes: 30 },
      ],
    });
  });
});

describe('CalendarApiClient.listarEventos', () => {
  beforeEach(() => {
    mocksGoogleapis().__list.mockClear();
  });

  it('repassa timeMin/timeMax e calendarId=primary para events.list', async () => {
    const { __list } = mocksGoogleapis();
    __list.mockResolvedValueOnce({ data: { items: [] } });

    await buildClient().listarEventos(
      'rt-123',
      '2026-09-01T00:00:00.000Z',
      '2026-10-01T00:00:00.000Z',
    );

    expect(__list).toHaveBeenCalledWith({
      calendarId: 'primary',
      timeMin: '2026-09-01T00:00:00.000Z',
      timeMax: '2026-10-01T00:00:00.000Z',
      singleEvents: true,
      orderBy: 'startTime',
    });
  });

  it('mapeia os itens do Google para o shape EventoCalendario esperado pelo app', async () => {
    const { __list } = mocksGoogleapis();
    __list.mockResolvedValueOnce({
      data: {
        items: [
          {
            id: 'ev1',
            summary: 'Reunião',
            description: 'Pauta',
            start: { dateTime: '2026-09-01T15:00:00-03:00' },
            end: { dateTime: '2026-09-01T16:00:00-03:00' },
          },
        ],
      },
    });

    const eventos = await buildClient().listarEventos(
      'rt-123',
      '2026-09-01T00:00:00.000Z',
      '2026-10-01T00:00:00.000Z',
    );

    expect(eventos).toEqual([
      {
        id: 'ev1',
        titulo: 'Reunião',
        descricao: 'Pauta',
        dataHoraInicio: '2026-09-01T15:00:00-03:00',
        dataHoraFim: '2026-09-01T16:00:00-03:00',
      },
    ]);
  });

  it('retorna lista vazia quando o Google não devolve items', async () => {
    const { __list } = mocksGoogleapis();
    __list.mockResolvedValueOnce({ data: {} });

    const eventos = await buildClient().listarEventos(
      'rt-123',
      '2026-09-01T00:00:00.000Z',
      '2026-10-01T00:00:00.000Z',
    );

    expect(eventos).toEqual([]);
  });
});

describe('CalendarApiClient.criarEventoCompleto', () => {
  beforeEach(() => {
    mocksGoogleapis().__insert.mockClear();
  });

  it('preserva o offset de início e fim, igual a criarEvento', async () => {
    const { __insert } = mocksGoogleapis();
    __insert.mockResolvedValueOnce({ data: { id: 'ev1' } });

    await buildClient().criarEventoCompleto('rt-123', {
      titulo: 'Consulta',
      descricao: 'Com o dentista',
      dataHoraInicio: '2026-09-01T15:00:00-03:00',
      dataHoraFim: '2026-09-01T16:00:00-03:00',
    });

    const body = corpoEnviado();
    expect(body).toEqual({
      summary: 'Consulta',
      description: 'Com o dentista',
      start: { dateTime: '2026-09-01T15:00:00-03:00' },
      end: { dateTime: '2026-09-01T16:00:00-03:00' },
    });
  });

  it('retorna o evento criado (com o id real do Google) mapeado para EventoCalendario', async () => {
    const { __insert } = mocksGoogleapis();
    __insert.mockResolvedValueOnce({
      data: {
        id: 'ev-real-id',
        summary: 'Consulta',
        description: 'Com o dentista',
        start: { dateTime: '2026-09-01T15:00:00-03:00' },
        end: { dateTime: '2026-09-01T16:00:00-03:00' },
      },
    });

    const evento = await buildClient().criarEventoCompleto('rt-123', {
      titulo: 'Consulta',
      descricao: 'Com o dentista',
      dataHoraInicio: '2026-09-01T15:00:00-03:00',
      dataHoraFim: '2026-09-01T16:00:00-03:00',
    });

    expect(evento.id).toBe('ev-real-id');
  });
});

describe('CalendarApiClient.atualizarEvento', () => {
  beforeEach(() => {
    mocksGoogleapis().__patch.mockClear();
  });

  it('usa events.patch (não events.update) para não apagar attendees/reminders/location do evento real', async () => {
    const { __patch } = mocksGoogleapis();
    __patch.mockResolvedValueOnce({ data: { id: 'ev1' } });

    await buildClient().atualizarEvento('rt-123', 'ev1', {
      titulo: 'Consulta remarcada',
      descricao: 'Com o dentista',
      dataHoraInicio: '2026-09-01T15:00:00-03:00',
      dataHoraFim: '2026-09-01T16:00:00-03:00',
    });

    expect(__patch).toHaveBeenCalledTimes(1);
    expect(__patch).toHaveBeenCalledWith({
      calendarId: 'primary',
      eventId: 'ev1',
      requestBody: {
        summary: 'Consulta remarcada',
        description: 'Com o dentista',
        start: { dateTime: '2026-09-01T15:00:00-03:00' },
        end: { dateTime: '2026-09-01T16:00:00-03:00' },
      },
    });
  });

  it('preserva o offset do usuário no start/end enviados ao patch', async () => {
    const { __patch } = mocksGoogleapis();
    __patch.mockResolvedValueOnce({ data: {} });

    await buildClient().atualizarEvento('rt-123', 'ev1', {
      titulo: 'Reunião',
      descricao: '',
      dataHoraInicio: '2026-09-01T23:50:00+05:30',
      dataHoraFim: '2026-09-02T00:20:00+05:30',
    });

    const body = __patch.mock.calls[0][0].requestBody;
    expect(body.start.dateTime).toBe('2026-09-01T23:50:00+05:30');
    expect(body.end.dateTime).toBe('2026-09-02T00:20:00+05:30');
  });
});

describe('CalendarApiClient.deletarEvento', () => {
  it('chama events.delete com calendarId=primary e o eventId informado', async () => {
    const { __delete } = mocksGoogleapis();
    __delete.mockClear().mockResolvedValueOnce({ data: {} });

    await buildClient().deletarEvento('rt-123', 'ev1');

    expect(__delete).toHaveBeenCalledWith({
      calendarId: 'primary',
      eventId: 'ev1',
    });
  });
});
