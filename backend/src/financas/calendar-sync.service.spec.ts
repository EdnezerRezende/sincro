import { FinanceCalendarSyncService } from './calendar-sync.service';

function buildDeps() {
  const calendarApiClient = {
    criarEventoCompleto: jest.fn().mockResolvedValue({ id: 'evt-1' }),
    atualizarEvento: jest.fn().mockResolvedValue({ id: 'evt-1' }),
    deletarEvento: jest.fn().mockResolvedValue(undefined),
  };
  const gmailConnectionsService = {
    getDecryptedRefreshToken: jest.fn().mockResolvedValue('refresh-token'),
  };
  return { calendarApiClient, gmailConnectionsService };
}

const lancamentoBase = {
  id: 'lanc-1',
  descricao: 'Fatura Nubank',
  instituicao: 'Nubank',
  valor: 512.4,
  dataVencimento: new Date(Date.UTC(2026, 9, 10)),
  googleEventId: null as string | null,
};

describe('FinanceCalendarSyncService — syncOnConfirm', () => {
  it('creates a new event when the lançamento has no googleEventId yet', async () => {
    const deps = buildDeps();
    const service = new FinanceCalendarSyncService(deps.calendarApiClient as any, deps.gmailConnectionsService as any);

    const eventId = await service.syncOnConfirm('user-1', lancamentoBase as any);

    expect(deps.calendarApiClient.criarEventoCompleto).toHaveBeenCalledWith('refresh-token', {
      titulo: 'Pagar: Nubank · Fatura Nubank',
      descricao: 'Valor: R$ 512.40',
      dataHoraInicio: '2026-10-10',
      dataHoraFim: '2026-10-10',
      ehDiaInteiro: true,
    });
    expect(eventId).toBe('evt-1');
  });

  it('updates the existing event instead of creating a new one', async () => {
    const deps = buildDeps();
    const service = new FinanceCalendarSyncService(deps.calendarApiClient as any, deps.gmailConnectionsService as any);

    const eventId = await service.syncOnConfirm('user-1', { ...lancamentoBase, googleEventId: 'evt-existing' } as any);

    expect(deps.calendarApiClient.atualizarEvento).toHaveBeenCalledWith('refresh-token', 'evt-existing', expect.any(Object));
    expect(deps.calendarApiClient.criarEventoCompleto).not.toHaveBeenCalled();
    expect(eventId).toBe('evt-existing');
  });

  it('never throws when the Calendar call fails, and returns the prior googleEventId', async () => {
    const deps = buildDeps();
    deps.calendarApiClient.criarEventoCompleto.mockRejectedValue(new Error('sem escopo de agenda'));
    const service = new FinanceCalendarSyncService(deps.calendarApiClient as any, deps.gmailConnectionsService as any);

    const eventId = await service.syncOnConfirm('user-1', lancamentoBase as any);

    expect(eventId).toBeNull();
  });

  it('does nothing when the user has no Gmail connection', async () => {
    const deps = buildDeps();
    deps.gmailConnectionsService.getDecryptedRefreshToken.mockResolvedValue(null);
    const service = new FinanceCalendarSyncService(deps.calendarApiClient as any, deps.gmailConnectionsService as any);

    const eventId = await service.syncOnConfirm('user-1', lancamentoBase as any);

    expect(deps.calendarApiClient.criarEventoCompleto).not.toHaveBeenCalled();
    expect(eventId).toBeNull();
  });
});

describe('FinanceCalendarSyncService — removeEvent', () => {
  it('deletes the event when a googleEventId is present', async () => {
    const deps = buildDeps();
    const service = new FinanceCalendarSyncService(deps.calendarApiClient as any, deps.gmailConnectionsService as any);

    await service.removeEvent('user-1', 'evt-1');

    expect(deps.calendarApiClient.deletarEvento).toHaveBeenCalledWith('refresh-token', 'evt-1');
  });

  it('does nothing when googleEventId is null', async () => {
    const deps = buildDeps();
    const service = new FinanceCalendarSyncService(deps.calendarApiClient as any, deps.gmailConnectionsService as any);

    await service.removeEvent('user-1', null);

    expect(deps.calendarApiClient.deletarEvento).not.toHaveBeenCalled();
  });

  it('never throws when the delete call fails', async () => {
    const deps = buildDeps();
    deps.calendarApiClient.deletarEvento.mockRejectedValue(new Error('token revogado'));
    const service = new FinanceCalendarSyncService(deps.calendarApiClient as any, deps.gmailConnectionsService as any);

    await expect(service.removeEvent('user-1', 'evt-1')).resolves.toBeUndefined();
  });
});
