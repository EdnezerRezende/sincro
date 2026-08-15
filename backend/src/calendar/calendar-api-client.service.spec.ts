import { CalendarApiClient } from './calendar-api-client.service';

jest.mock('googleapis', () => {
  const insert = jest.fn().mockResolvedValue({ data: {} });
  return {
    google: { calendar: jest.fn(() => ({ events: { insert } })) },
    __insert: insert,
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

describe('CalendarApiClient.criarEvento', () => {
  beforeEach(() => {
    const { __insert } = jest.requireMock('googleapis');
    __insert.mockClear();
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
