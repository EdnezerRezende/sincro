import { FinanceConnectionsService } from './finance-connections.service';

function buildDeps() {
  const prisma = {
    financeConnection: {
      upsert: jest.fn(),
      findMany: jest.fn(),
      findFirst: jest.fn(),
      delete: jest.fn(),
      count: jest.fn(),
    },
    financeAccount: { deleteMany: jest.fn() },
    boletoDda: { deleteMany: jest.fn() },
  };
  const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1' }) };
  const pluggyApiClient = {
    createConnectToken: jest.fn().mockResolvedValue('connect-token-abc'),
    getItem: jest.fn().mockResolvedValue({ id: 'item-1', connector: { name: 'Banco Teste' }, status: 'UPDATED' }),
    deleteItem: jest.fn().mockResolvedValue(undefined),
  };
  return { prisma, usersService, pluggyApiClient };
}

describe('FinanceConnectionsService', () => {
  it('returns a connect token from Pluggy', async () => {
    const { prisma, usersService, pluggyApiClient } = buildDeps();
    const service = new FinanceConnectionsService(prisma as any, usersService as any, pluggyApiClient as any);

    const result = await service.createConnectToken();

    expect(result).toEqual({ connectToken: 'connect-token-abc' });
  });

  it('finalizes a connection by fetching the item and upserting the row', async () => {
    const { prisma, usersService, pluggyApiClient } = buildDeps();
    prisma.financeConnection.upsert.mockResolvedValue({ id: 'conn-1', instituicao: 'Banco Teste', status: 'UPDATED' });
    const service = new FinanceConnectionsService(prisma as any, usersService as any, pluggyApiClient as any);

    const result = await service.finalizeConnection('fb1', 'item-1');

    expect(pluggyApiClient.getItem).toHaveBeenCalledWith('item-1');
    expect(prisma.financeConnection.upsert).toHaveBeenCalledWith({
      where: { userId_pluggyItemId: { userId: 'u1', pluggyItemId: 'item-1' } },
      update: { status: 'UPDATED', instituicao: 'Banco Teste' },
      create: { userId: 'u1', pluggyItemId: 'item-1', instituicao: 'Banco Teste', status: 'UPDATED' },
    });
    expect(result).toEqual({ id: 'conn-1', instituicao: 'Banco Teste', status: 'UPDATED' });
  });

  it('lists connections scoped to the resolved user', async () => {
    const { prisma, usersService, pluggyApiClient } = buildDeps();
    prisma.financeConnection.findMany.mockResolvedValue([{ id: 'conn-1', instituicao: 'Banco Teste', status: 'UPDATED' }]);
    const service = new FinanceConnectionsService(prisma as any, usersService as any, pluggyApiClient as any);

    const result = await service.listConnections('fb1');

    expect(prisma.financeConnection.findMany).toHaveBeenCalledWith({
      where: { userId: 'u1' },
      select: { id: true, instituicao: true, status: true },
    });
    expect(result).toEqual([{ id: 'conn-1', instituicao: 'Banco Teste', status: 'UPDATED' }]);
  });

  it('disconnect deletes the Pluggy item and local rows, keeping boletos when other connections remain', async () => {
    const { prisma, usersService, pluggyApiClient } = buildDeps();
    prisma.financeConnection.findFirst.mockResolvedValue({ id: 'conn-1', userId: 'u1', pluggyItemId: 'item-1' });
    prisma.financeConnection.count.mockResolvedValue(1);
    const service = new FinanceConnectionsService(prisma as any, usersService as any, pluggyApiClient as any);

    await service.disconnect('fb1', 'conn-1');

    expect(pluggyApiClient.deleteItem).toHaveBeenCalledWith('item-1');
    expect(prisma.financeAccount.deleteMany).toHaveBeenCalledWith({ where: { conexaoId: 'conn-1' } });
    expect(prisma.financeConnection.delete).toHaveBeenCalledWith({ where: { id: 'conn-1' } });
    expect(prisma.boletoDda.deleteMany).not.toHaveBeenCalled();
  });

  it('disconnect also wipes boletos when it was the last connection', async () => {
    const { prisma, usersService, pluggyApiClient } = buildDeps();
    prisma.financeConnection.findFirst.mockResolvedValue({ id: 'conn-1', userId: 'u1', pluggyItemId: 'item-1' });
    prisma.financeConnection.count.mockResolvedValue(0);
    const service = new FinanceConnectionsService(prisma as any, usersService as any, pluggyApiClient as any);

    await service.disconnect('fb1', 'conn-1');

    expect(prisma.boletoDda.deleteMany).toHaveBeenCalledWith({ where: { userId: 'u1' } });
  });

  it('disconnect still cleans up local rows when the Pluggy delete call fails', async () => {
    const { prisma, usersService, pluggyApiClient } = buildDeps();
    prisma.financeConnection.findFirst.mockResolvedValue({ id: 'conn-1', userId: 'u1', pluggyItemId: 'item-1' });
    prisma.financeConnection.count.mockResolvedValue(0);
    pluggyApiClient.deleteItem.mockRejectedValue(new Error('already revoked'));
    const service = new FinanceConnectionsService(prisma as any, usersService as any, pluggyApiClient as any);

    await expect(service.disconnect('fb1', 'conn-1')).resolves.not.toThrow();
    expect(prisma.financeConnection.delete).toHaveBeenCalledWith({ where: { id: 'conn-1' } });
  });
});
