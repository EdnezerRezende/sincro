import { FinanceSyncService } from './finance-sync.service';

function buildDeps() {
  const prisma = {
    financeConnection: { findUnique: jest.fn(), findMany: jest.fn() },
    financeAccount: { upsert: jest.fn() },
    boletoDda: { upsert: jest.fn() },
  };
  const pluggyApiClient = {
    listAccounts: jest.fn().mockResolvedValue([]),
    listBoletos: jest.fn().mockResolvedValue([]),
  };
  const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1' }) };
  return { prisma, pluggyApiClient, usersService };
}

describe('FinanceSyncService', () => {
  it('does nothing when the connection no longer exists', async () => {
    const { prisma, pluggyApiClient, usersService } = buildDeps();
    prisma.financeConnection.findUnique.mockResolvedValue(null);
    const service = new FinanceSyncService(prisma as any, pluggyApiClient as any, usersService as any);

    await service.syncConnection('missing');

    expect(pluggyApiClient.listAccounts).not.toHaveBeenCalled();
  });

  it('upserts a BANK account as CORRENTE and a CREDIT account as CARTAO_CREDITO', async () => {
    const { prisma, pluggyApiClient, usersService } = buildDeps();
    prisma.financeConnection.findUnique.mockResolvedValue({ id: 'conn-1', userId: 'u1', pluggyItemId: 'item-1' });
    pluggyApiClient.listAccounts.mockResolvedValue([
      { id: 'acc-1', type: 'BANK', name: 'Conta Corrente', balance: 1500 },
      { id: 'acc-2', type: 'CREDIT', name: 'Cartão', balance: 400, creditData: { balanceCloseDate: '2026-08-10' } },
    ]);
    const service = new FinanceSyncService(prisma as any, pluggyApiClient as any, usersService as any);

    await service.syncConnection('conn-1');

    expect(prisma.financeAccount.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { conexaoId_pluggyAccountId: { conexaoId: 'conn-1', pluggyAccountId: 'acc-1' } },
        create: expect.objectContaining({ tipo: 'CORRENTE', saldoOuFatura: 1500, vencimentoFatura: null }),
      }),
    );
    expect(prisma.financeAccount.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { conexaoId_pluggyAccountId: { conexaoId: 'conn-1', pluggyAccountId: 'acc-2' } },
        create: expect.objectContaining({ tipo: 'CARTAO_CREDITO', saldoOuFatura: 400, vencimentoFatura: new Date('2026-08-10') }),
      }),
    );
  });

  it('upserts boletos scoped to the connection user', async () => {
    const { prisma, pluggyApiClient, usersService } = buildDeps();
    prisma.financeConnection.findUnique.mockResolvedValue({ id: 'conn-1', userId: 'u1', pluggyItemId: 'item-1' });
    pluggyApiClient.listBoletos.mockResolvedValue([
      { codigoBarras: '123456', valor: 100, vencimento: '2026-08-05' },
    ]);
    const service = new FinanceSyncService(prisma as any, pluggyApiClient as any, usersService as any);

    await service.syncConnection('conn-1');

    expect(prisma.boletoDda.upsert).toHaveBeenCalledWith({
      where: { userId_codigoBarras: { userId: 'u1', codigoBarras: '123456' } },
      update: { valor: 100, vencimento: new Date('2026-08-05') },
      create: { userId: 'u1', codigoBarras: '123456', valor: 100, vencimento: new Date('2026-08-05') },
    });
  });

  it('syncAllForUser syncs every connection belonging to the user', async () => {
    const { prisma, pluggyApiClient, usersService } = buildDeps();
    prisma.financeConnection.findMany.mockResolvedValue([{ id: 'conn-1' }, { id: 'conn-2' }]);
    prisma.financeConnection.findUnique
      .mockResolvedValueOnce({ id: 'conn-1', userId: 'u1', pluggyItemId: 'item-1' })
      .mockResolvedValueOnce({ id: 'conn-2', userId: 'u1', pluggyItemId: 'item-2' });
    const service = new FinanceSyncService(prisma as any, pluggyApiClient as any, usersService as any);

    await service.syncAllForUser('fb1');

    expect(prisma.financeConnection.findMany).toHaveBeenCalledWith({ where: { userId: 'u1' }, select: { id: true } });
    expect(pluggyApiClient.listAccounts).toHaveBeenCalledWith('item-1');
    expect(pluggyApiClient.listAccounts).toHaveBeenCalledWith('item-2');
  });
});
