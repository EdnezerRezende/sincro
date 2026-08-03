import { EmailSyncService } from './email-sync.service';

function buildDeps() {
  const prisma = {
    gmailConnection: { findUnique: jest.fn(), update: jest.fn() },
    user: { findUniqueOrThrow: jest.fn().mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', plano: 'simples' }) },
    emailSummary: { findUnique: jest.fn().mockResolvedValue(null), create: jest.fn(), findMany: jest.fn() },
  };
  const gmailApiClient = { fetchInitialUnread: jest.fn(), fetchIncremental: jest.fn() };
  const connectionsService = { getDecryptedRefreshToken: jest.fn().mockResolvedValue('rt-123') };
  const sensoryProfileService = { get: jest.fn().mockResolvedValue(null) };
  const heuristicClassifier = { classify: jest.fn().mockResolvedValue({ categoria: 'PODE_ESPERAR', resumoCurto: 'ok' }) };
  const llmClassifier = { classify: jest.fn().mockResolvedValue({ categoria: 'PRECISA_ATENCAO', resumoCurto: 'llm ok' }) };
  const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1', firebaseUid: 'fb1' }) };

  return { prisma, gmailApiClient, connectionsService, sensoryProfileService, heuristicClassifier, llmClassifier, usersService };
}

function buildService(deps: ReturnType<typeof buildDeps>) {
  return new EmailSyncService(
    deps.prisma as any,
    deps.gmailApiClient as any,
    deps.connectionsService as any,
    deps.sensoryProfileService as any,
    deps.heuristicClassifier as any,
    deps.llmClassifier as any,
    deps.usersService as any,
  );
}

describe('EmailSyncService', () => {
  it('returns zero and does nothing when the user has no Gmail connection', async () => {
    const deps = buildDeps();
    deps.prisma.gmailConnection.findUnique.mockResolvedValue(null);
    const service = buildService(deps);

    const result = await service.syncUser('u1');

    expect(result).toEqual({ novosPrecisamAtencao: 0 });
    expect(deps.gmailApiClient.fetchInitialUnread).not.toHaveBeenCalled();
  });

  it('performs a full initial sync when there is no lastHistoryId yet', async () => {
    const deps = buildDeps();
    deps.prisma.gmailConnection.findUnique.mockResolvedValue({ userId: 'u1', lastHistoryId: null });
    deps.gmailApiClient.fetchInitialUnread.mockResolvedValue({
      emails: [{ gmailMessageId: 'm1', remetente: 'x@example.com', assunto: 'Assunto', corpo: 'corpo', recebidoEm: new Date() }],
      historyId: 'h1',
    });
    const service = buildService(deps);

    const result = await service.syncUser('u1');

    expect(deps.gmailApiClient.fetchInitialUnread).toHaveBeenCalledWith('rt-123');
    expect(deps.heuristicClassifier.classify).toHaveBeenCalled();
    expect(deps.prisma.emailSummary.create).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ userId: 'u1', gmailMessageId: 'm1' }) }),
    );
    expect(deps.prisma.gmailConnection.update).toHaveBeenCalledWith({
      where: { userId: 'u1' },
      data: { lastHistoryId: 'h1', ultimaSincronizacao: expect.any(Date) },
    });
    expect(result.novosPrecisamAtencao).toBe(0);
  });

  it('performs an incremental sync when a lastHistoryId is stored', async () => {
    const deps = buildDeps();
    deps.prisma.gmailConnection.findUnique.mockResolvedValue({ userId: 'u1', lastHistoryId: 'h1' });
    deps.gmailApiClient.fetchIncremental.mockResolvedValue({
      emails: [{ gmailMessageId: 'm2', remetente: 'x@example.com', assunto: 'Novo', corpo: '', recebidoEm: new Date() }],
      historyId: 'h2',
      historyExpired: false,
    });
    const service = buildService(deps);

    await service.syncUser('u1');

    expect(deps.gmailApiClient.fetchIncremental).toHaveBeenCalledWith('rt-123', 'h1');
    expect(deps.gmailApiClient.fetchInitialUnread).not.toHaveBeenCalled();
  });

  it('falls back to a full sync when the stored historyId has expired', async () => {
    const deps = buildDeps();
    deps.prisma.gmailConnection.findUnique.mockResolvedValue({ userId: 'u1', lastHistoryId: 'stale' });
    deps.gmailApiClient.fetchIncremental.mockResolvedValue({ emails: [], historyId: null, historyExpired: true });
    deps.gmailApiClient.fetchInitialUnread.mockResolvedValue({ emails: [], historyId: 'h-fresh' });
    const service = buildService(deps);

    await service.syncUser('u1');

    expect(deps.gmailApiClient.fetchInitialUnread).toHaveBeenCalledWith('rt-123');
  });

  it('skips messages that were already synced (deduplication)', async () => {
    const deps = buildDeps();
    deps.prisma.gmailConnection.findUnique.mockResolvedValue({ userId: 'u1', lastHistoryId: null });
    deps.prisma.emailSummary.findUnique.mockResolvedValue({ id: 'existing' });
    deps.gmailApiClient.fetchInitialUnread.mockResolvedValue({
      emails: [{ gmailMessageId: 'already-there', remetente: 'x@example.com', assunto: 'A', corpo: '', recebidoEm: new Date() }],
      historyId: 'h1',
    });
    const service = buildService(deps);

    await service.syncUser('u1');

    expect(deps.prisma.emailSummary.create).not.toHaveBeenCalled();
  });

  it('does not abort the loop or skip the lastHistoryId update when create() hits a duplicate-key race', async () => {
    const deps = buildDeps();
    deps.prisma.gmailConnection.findUnique.mockResolvedValue({ userId: 'u1', lastHistoryId: null });
    // The pre-filter finds nothing (simulating a concurrent run that inserted this row after the
    // findUnique check but before create() below), so create() itself hits the unique constraint.
    deps.prisma.emailSummary.findUnique.mockResolvedValue(null);
    deps.prisma.emailSummary.create.mockRejectedValue(
      Object.assign(new Error('Unique constraint failed'), { code: 'P2002' }),
    );
    deps.gmailApiClient.fetchInitialUnread.mockResolvedValue({
      emails: [
        { gmailMessageId: 'raced', remetente: 'x@example.com', assunto: 'A', corpo: '', recebidoEm: new Date() },
      ],
      historyId: 'h1',
    });
    const service = buildService(deps);

    const result = await service.syncUser('u1');

    expect(result.novosPrecisamAtencao).toBe(0);
    expect(deps.prisma.gmailConnection.update).toHaveBeenCalledWith({
      where: { userId: 'u1' },
      data: { lastHistoryId: 'h1', ultimaSincronizacao: expect.any(Date) },
    });
  });

  it('does not abort the loop or skip the lastHistoryId update when create() throws an unrelated error', async () => {
    const deps = buildDeps();
    deps.prisma.gmailConnection.findUnique.mockResolvedValue({ userId: 'u1', lastHistoryId: null });
    deps.prisma.emailSummary.findUnique.mockResolvedValue(null);
    deps.prisma.emailSummary.create.mockRejectedValue(new Error('connection reset'));
    deps.gmailApiClient.fetchInitialUnread.mockResolvedValue({
      emails: [
        { gmailMessageId: 'm1', remetente: 'x@example.com', assunto: 'A', corpo: '', recebidoEm: new Date() },
      ],
      historyId: 'h1',
    });
    const service = buildService(deps);

    const result = await service.syncUser('u1');

    expect(result.novosPrecisamAtencao).toBe(0);
    expect(deps.prisma.gmailConnection.update).toHaveBeenCalledWith({
      where: { userId: 'u1' },
      data: { lastHistoryId: 'h1', ultimaSincronizacao: expect.any(Date) },
    });
  });

  it('uses the LLM classifier when the user is on plano pro', async () => {
    const deps = buildDeps();
    deps.prisma.user.findUniqueOrThrow.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', plano: 'pro' });
    deps.prisma.gmailConnection.findUnique.mockResolvedValue({ userId: 'u1', lastHistoryId: null });
    deps.gmailApiClient.fetchInitialUnread.mockResolvedValue({
      emails: [{ gmailMessageId: 'm1', remetente: 'x@example.com', assunto: 'A', corpo: '', recebidoEm: new Date() }],
      historyId: 'h1',
    });
    const service = buildService(deps);

    const result = await service.syncUser('u1');

    expect(deps.llmClassifier.classify).toHaveBeenCalled();
    expect(deps.heuristicClassifier.classify).not.toHaveBeenCalled();
    expect(result.novosPrecisamAtencao).toBe(1);
  });

  it('falls back to PODE_ESPERAR when the classifier itself throws', async () => {
    const deps = buildDeps();
    deps.prisma.gmailConnection.findUnique.mockResolvedValue({ userId: 'u1', lastHistoryId: null });
    deps.heuristicClassifier.classify.mockRejectedValue(new Error('boom'));
    deps.gmailApiClient.fetchInitialUnread.mockResolvedValue({
      emails: [{ gmailMessageId: 'm1', remetente: 'x@example.com', assunto: 'Assunto original', corpo: '', recebidoEm: new Date() }],
      historyId: 'h1',
    });
    const service = buildService(deps);

    await service.syncUser('u1');

    expect(deps.prisma.emailSummary.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ categoria: 'PODE_ESPERAR', resumoCurto: 'Assunto original' }),
      }),
    );
  });

  it('lists summaries scoped to the resolved user, most recent first', async () => {
    const deps = buildDeps();
    deps.prisma.emailSummary.findMany.mockResolvedValue([]);
    const service = buildService(deps);

    await service.list('fb1');

    expect(deps.prisma.emailSummary.findMany).toHaveBeenCalledWith({
      where: { userId: 'u1' },
      orderBy: { recebidoEm: 'desc' },
      take: 100,
      select: {
        id: true,
        gmailMessageId: true,
        remetente: true,
        assunto: true,
        resumoCurto: true,
        categoria: true,
        recebidoEm: true,
      },
    });
  });
});
