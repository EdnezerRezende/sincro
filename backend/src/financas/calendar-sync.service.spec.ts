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
  it('creates a new event when the lançamento has no googleEventId yet, tagged as FINANCEIRO', async () => {
    const deps = buildDeps();
    const service = new FinanceCalendarSyncService(deps.calendarApiClient as any, deps.gmailConnectionsService as any);

    const eventId = await service.syncOnConfirm('user-1', lancamentoBase as any);

    expect(deps.calendarApiClient.criarEventoCompleto).toHaveBeenCalledWith('refresh-token', {
      titulo: 'Pagar: Nubank · Fatura Nubank',
      descricao: 'Valor: R$ 512.40',
      dataHoraInicio: '2026-10-10',
      dataHoraFim: '2026-10-10',
      ehDiaInteiro: true,
      lembretesMinutosAntes: [1440],
      categoria: 'FINANCEIRO',
      lancamentoId: 'lanc-1',
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
  it('deletes the event when a googleEventId is present and returns true', async () => {
    const deps = buildDeps();
    const service = new FinanceCalendarSyncService(deps.calendarApiClient as any, deps.gmailConnectionsService as any);

    const removido = await service.removeEvent('user-1', 'evt-1');

    expect(deps.calendarApiClient.deletarEvento).toHaveBeenCalledWith('refresh-token', 'evt-1');
    expect(removido).toBe(true);
  });

  it('does nothing and returns true when googleEventId is null (nothing to remove)', async () => {
    const deps = buildDeps();
    const service = new FinanceCalendarSyncService(deps.calendarApiClient as any, deps.gmailConnectionsService as any);

    const removido = await service.removeEvent('user-1', null);

    expect(deps.calendarApiClient.deletarEvento).not.toHaveBeenCalled();
    expect(removido).toBe(true);
  });

  it('returns false without throwing when there is no Gmail connection', async () => {
    const deps = buildDeps();
    deps.gmailConnectionsService.getDecryptedRefreshToken.mockResolvedValue(null);
    const service = new FinanceCalendarSyncService(deps.calendarApiClient as any, deps.gmailConnectionsService as any);

    const removido = await service.removeEvent('user-1', 'evt-1');

    expect(deps.calendarApiClient.deletarEvento).not.toHaveBeenCalled();
    expect(removido).toBe(false);
  });

  it('returns false without throwing when the delete call fails for an unrelated reason', async () => {
    const deps = buildDeps();
    deps.calendarApiClient.deletarEvento.mockRejectedValue(new Error('token revogado'));
    const service = new FinanceCalendarSyncService(deps.calendarApiClient as any, deps.gmailConnectionsService as any);

    await expect(service.removeEvent('user-1', 'evt-1')).resolves.toBe(false);
  });

  it('returns true when the Calendar API reports the event is already gone (404)', async () => {
    const deps = buildDeps();
    const erro404 = Object.assign(new Error('Not Found'), { code: 404 });
    deps.calendarApiClient.deletarEvento.mockRejectedValue(erro404);
    const service = new FinanceCalendarSyncService(deps.calendarApiClient as any, deps.gmailConnectionsService as any);

    await expect(service.removeEvent('user-1', 'evt-1')).resolves.toBe(true);
  });

  it('returns true when the Calendar API reports the event is gone (410)', async () => {
    const deps = buildDeps();
    const erro410 = Object.assign(new Error('Gone'), { response: { status: 410 } });
    deps.calendarApiClient.deletarEvento.mockRejectedValue(erro410);
    const service = new FinanceCalendarSyncService(deps.calendarApiClient as any, deps.gmailConnectionsService as any);

    await expect(service.removeEvent('user-1', 'evt-1')).resolves.toBe(true);
  });
});
