import { EmailSyncService } from './email-sync.service';

function buildDeps() {
  const prisma = {
    gmailConnection: { findUnique: jest.fn(), update: jest.fn() },
    user: { findUniqueOrThrow: jest.fn().mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', plano: 'simples' }) },
    emailSummary: {
      findUnique: jest.fn().mockResolvedValue(null),
      findFirst: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      updateMany: jest.fn(),
      findMany: jest.fn().mockResolvedValue([]),
      delete: jest.fn(),
    },
    $executeRaw: jest.fn(),
  };
  const gmailApiClient = {
    fetchInitialUnread: jest.fn(),
    fetchIncremental: jest.fn(),
    fetchFullBody: jest.fn(),
    listarIdsComMarcador: jest.fn().mockResolvedValue({ labelId: null, ids: new Set<string>() }),
  };
  const connectionsService = { getDecryptedRefreshToken: jest.fn().mockResolvedValue('rt-123') };
  const sensoryProfileService = { get: jest.fn().mockResolvedValue(null) };
  const heuristicClassifier = { classify: jest.fn().mockResolvedValue({ categoria: 'PODE_ESPERAR', resumoCurto: 'ok' }) };
  const llmClassifier = { classify: jest.fn().mockResolvedValue({ categoria: 'PRECISA_ATENCAO', resumoCurto: 'llm ok' }) };
  const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1', firebaseUid: 'fb1' }) };
  const financeProcessor = { processar: jest.fn().mockResolvedValue({ transitorio: false, classe: null, acao: 'nada' }) };

  return {
    prisma,
    gmailApiClient,
    connectionsService,
    sensoryProfileService,
    heuristicClassifier,
    llmClassifier,
    usersService,
    financeProcessor,
  };
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
    deps.financeProcessor as any,
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

  it('does not abort the loop, but skips the lastHistoryId update, when create() throws a non-duplicate-key error', async () => {
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

    // The loop still finishes (no throw out of syncUser), but since this message was never
    // actually persisted for a real (non-duplicate) reason, the cursor must not advance past
    // it — otherwise fetchIncremental would never look at it again and it'd be lost forever.
    expect(result.novosPrecisamAtencao).toBe(0);
    expect(deps.prisma.gmailConnection.update).not.toHaveBeenCalled();
  });

  it('does not advance the cursor when create() rejects with a non-P2002 Prisma error code', async () => {
    const deps = buildDeps();
    deps.prisma.gmailConnection.findUnique.mockResolvedValue({ userId: 'u1', lastHistoryId: 'h0' });
    deps.prisma.emailSummary.findUnique.mockResolvedValue(null);
    deps.prisma.emailSummary.create.mockRejectedValue(
      Object.assign(new Error('Server has closed the connection'), { code: 'P1017' }),
    );
    deps.heuristicClassifier.classify.mockResolvedValue({ categoria: 'PODE_ESPERAR', resumoCurto: 'ok' });
    deps.gmailApiClient.fetchIncremental.mockResolvedValue({
      emails: [
        { gmailMessageId: 'm-transient', remetente: 'x@example.com', assunto: 'A', corpo: '', recebidoEm: new Date() },
      ],
      historyId: 'h1',
      historyExpired: false,
    });
    const service = buildService(deps);

    const result = await service.syncUser('u1');

    expect(result.novosPrecisamAtencao).toBe(0);
    expect(deps.prisma.emailSummary.create).toHaveBeenCalled();
    expect(deps.prisma.gmailConnection.update).not.toHaveBeenCalled();
  });

  it('still advances the cursor when every message in the cycle persists successfully', async () => {
    const deps = buildDeps();
    deps.prisma.gmailConnection.findUnique.mockResolvedValue({ userId: 'u1', lastHistoryId: 'h1' });
    deps.prisma.emailSummary.findUnique.mockResolvedValue(null);
    deps.heuristicClassifier.classify.mockResolvedValue({ categoria: 'PODE_ESPERAR', resumoCurto: 'ok' });
    deps.gmailApiClient.fetchIncremental.mockResolvedValue({
      emails: [
        { gmailMessageId: 'm-ok', remetente: 'x@example.com', assunto: 'A', corpo: '', recebidoEm: new Date() },
      ],
      historyId: 'h2',
      historyExpired: false,
    });
    const service = buildService(deps);

    await service.syncUser('u1');

    expect(deps.prisma.gmailConnection.update).toHaveBeenCalledWith({
      where: { userId: 'u1' },
      data: { lastHistoryId: 'h2', ultimaSincronizacao: expect.any(Date) },
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

  describe('getOwned', () => {
    it('returns the summary when it belongs to the authenticated user', async () => {
      const deps = buildDeps();
      const summary = { id: 'summary-1', userId: 'u1', gmailMessageId: 'msg-1' };
      deps.prisma.emailSummary.findFirst.mockResolvedValue(summary);
      const service = buildService(deps);

      const result = await service.getOwned('fb1', 'summary-1');

      expect(result).toEqual(summary);
      expect(deps.prisma.emailSummary.findFirst).toHaveBeenCalledWith({
        where: { id: 'summary-1', userId: 'u1' },
      });
    });

    it('throws NotFoundException when the summary does not exist or belongs to another user', async () => {
      const deps = buildDeps();
      deps.prisma.emailSummary.findFirst.mockResolvedValue(null);
      const service = buildService(deps);

      await expect(service.getOwned('fb1', 'someone-elses-summary')).rejects.toThrow(
        'E-mail não encontrado.',
      );
    });
  });

  describe('remover', () => {
    it('deletes the local row by id (arquivar/excluir take the row out of the inbox immediately, without waiting for the sync cron)', async () => {
      const deps = buildDeps();
      const service = buildService(deps);

      await service.remover('summary-1');

      expect(deps.prisma.emailSummary.delete).toHaveBeenCalledWith({ where: { id: 'summary-1' } });
    });
  });

  describe('EmailSyncService — finanças', () => {
    const email = {
      gmailMessageId: 'm1',
      remetente: 'Nubank <todomundo@nubank.com.br>',
      assunto: 'A fatura do seu cartão Nubank está fechada',
      corpo: 's',
      recebidoEm: new Date(),
      labelIds: ['INBOX'],
    };
    function comNovo(deps: ReturnType<typeof buildDeps>) {
      deps.prisma.gmailConnection.findUnique.mockResolvedValue({ userId: 'u1', lastHistoryId: null });
      deps.gmailApiClient.fetchInitialUnread.mockResolvedValue({ emails: [email], historyId: 'h1' });
    }

    it('(A) carimba versão e labelIds no summary novo', async () => {
      const deps = buildDeps();
      comNovo(deps);
      await buildService(deps).syncUser('u1');
      expect(deps.financeProcessor.processar).toHaveBeenCalledWith(
        'u1',
        'rt-123',
        expect.objectContaining({ gmailMessageId: 'm1' }),
        { marcado: false },
      );
      expect(deps.prisma.emailSummary.create).toHaveBeenCalledWith({
        data: expect.objectContaining({ labelIds: ['INBOX'], parserFinancasVersao: 2, parserFinancasTentativas: 0 }),
      });
    });

    it('(A) falha transitória grava versão null e tentativas 1', async () => {
      const deps = buildDeps();
      comNovo(deps);
      deps.financeProcessor.processar.mockResolvedValue({ transitorio: true, classe: 'transitorio-mensagem', acao: 'erro' });
      await buildService(deps).syncUser('u1');
      expect(deps.prisma.emailSummary.create).toHaveBeenCalledWith({
        data: expect.objectContaining({ parserFinancasVersao: null, parserFinancasTentativas: 1 }),
      });
    });

    it('(0) marcador: passa marcado=true e re-enfileira quem não tinha o label', async () => {
      const deps = buildDeps();
      comNovo(deps);
      deps.gmailApiClient.listarIdsComMarcador.mockResolvedValue({ labelId: 'Label_7', ids: new Set(['m1', 'm9']) });
      await buildService(deps).syncUser('u1');
      expect(deps.prisma.$executeRaw).toHaveBeenCalledTimes(1);
      expect(deps.financeProcessor.processar).toHaveBeenCalledWith('u1', 'rt-123', expect.anything(), { marcado: true });
      expect(deps.prisma.emailSummary.create).toHaveBeenCalledWith({
        data: expect.objectContaining({ labelIds: ['INBOX', 'Label_7'] }),
      });
    });

    it('(0) falha transitória no marcador não derruba o ciclo', async () => {
      const deps = buildDeps();
      comNovo(deps);
      deps.gmailApiClient.listarIdsComMarcador.mockRejectedValue(
        Object.assign(new Error('x'), { code: 503, response: { status: 503 }, config: {} }),
      );
      await expect(buildService(deps).syncUser('u1')).resolves.toBeDefined();
      expect(deps.financeProcessor.processar).toHaveBeenCalledWith('u1', 'rt-123', expect.anything(), { marcado: false });
    });

    it('(0) marcador indisponível: (A) carimba parserFinancasVersao null e ainda processa, (B) não roda neste ciclo', async () => {
      const deps = buildDeps();
      comNovo(deps);
      deps.gmailApiClient.listarIdsComMarcador.mockRejectedValue(
        Object.assign(new Error('x'), { code: 503, response: { status: 503 }, config: {} }),
      );
      await buildService(deps).syncUser('u1');
      expect(deps.financeProcessor.processar).toHaveBeenCalledWith('u1', 'rt-123', expect.objectContaining({ gmailMessageId: 'm1' }), { marcado: false });
      expect(deps.prisma.emailSummary.create).toHaveBeenCalledWith({
        data: expect.objectContaining({ parserFinancasVersao: null, parserFinancasTentativas: 0 }),
      });
      expect(deps.prisma.emailSummary.findMany).not.toHaveBeenCalled();
    });

    it('(B) reprocessa pendentes ordenados, carimba sucesso e zera tentativas', async () => {
      const deps = buildDeps();
      deps.prisma.gmailConnection.findUnique.mockResolvedValue({ userId: 'u1', lastHistoryId: 'h0' });
      deps.gmailApiClient.fetchIncremental.mockResolvedValue({ emails: [], historyId: 'h1', historyExpired: false });
      deps.prisma.emailSummary.findMany.mockResolvedValue([
        { id: 's1', gmailMessageId: 'm1', remetente: 'r', assunto: 'a', recebidoEm: new Date(), labelIds: [] },
      ]);
      await buildService(deps).syncUser('u1');
      expect(deps.prisma.emailSummary.findMany).toHaveBeenCalledWith({
        where: { userId: 'u1', OR: [{ parserFinancasVersao: null }, { parserFinancasVersao: { lt: 2 } }] },
        orderBy: [{ parserFinancasTentativas: 'asc' }, { recebidoEm: 'desc' }],
        take: 50,
      });
      expect(deps.prisma.emailSummary.update).toHaveBeenCalledWith({
        where: { id: 's1' },
        data: { parserFinancasVersao: 2, parserFinancasTentativas: 0, labelIds: [] },
      });
    });

    it('(B) transitório-mensagem incrementa e segue; transitório-conta incrementa e interrompe', async () => {
      const deps = buildDeps();
      deps.prisma.gmailConnection.findUnique.mockResolvedValue({ userId: 'u1', lastHistoryId: 'h0' });
      deps.gmailApiClient.fetchIncremental.mockResolvedValue({ emails: [], historyId: 'h1', historyExpired: false });
      deps.prisma.emailSummary.findMany.mockResolvedValue([
        { id: 's1', gmailMessageId: 'm1', remetente: 'r', assunto: 'a', recebidoEm: new Date(), labelIds: [], parserFinancasTentativas: 0 },
        { id: 's2', gmailMessageId: 'm2', remetente: 'r', assunto: 'a', recebidoEm: new Date(), labelIds: [], parserFinancasTentativas: 0 },
        { id: 's3', gmailMessageId: 'm3', remetente: 'r', assunto: 'a', recebidoEm: new Date(), labelIds: [], parserFinancasTentativas: 0 },
      ]);
      deps.financeProcessor.processar
        .mockResolvedValueOnce({ transitorio: true, classe: 'transitorio-mensagem', acao: 'erro' })
        .mockResolvedValueOnce({ transitorio: true, classe: 'transitorio-conta', acao: 'erro' });
      await buildService(deps).syncUser('u1');
      expect(deps.financeProcessor.processar).toHaveBeenCalledTimes(2);
      expect(deps.prisma.emailSummary.update).toHaveBeenNthCalledWith(1, {
        where: { id: 's1' },
        data: { parserFinancasTentativas: { increment: 1 } },
      });
      expect(deps.prisma.emailSummary.update).toHaveBeenNthCalledWith(2, {
        where: { id: 's2' },
        data: { parserFinancasTentativas: { increment: 1 } },
      });
    });

    it('(B) erro permanente carimba', async () => {
      const deps = buildDeps();
      deps.prisma.gmailConnection.findUnique.mockResolvedValue({ userId: 'u1', lastHistoryId: 'h0' });
      deps.gmailApiClient.fetchIncremental.mockResolvedValue({ emails: [], historyId: 'h1', historyExpired: false });
      deps.prisma.emailSummary.findMany.mockResolvedValue([
        { id: 's1', gmailMessageId: 'm1', remetente: 'r', assunto: 'a', recebidoEm: new Date(), labelIds: [] },
      ]);
      deps.financeProcessor.processar.mockResolvedValue({ transitorio: false, classe: 'permanente', acao: 'erro' });
      await buildService(deps).syncUser('u1');
      expect(deps.prisma.emailSummary.update).toHaveBeenCalledWith({
        where: { id: 's1' },
        data: { parserFinancasVersao: 2, parserFinancasTentativas: 0, labelIds: [] },
      });
    });
  });
});
