import { ContasService } from './contas.service';

function buildPrismaMock() {
  return {
    contaFinanceira: {
      findMany: jest.fn().mockResolvedValue([]),
      create: jest.fn(),
      update: jest.fn(),
      delete: jest.fn(),
      findFirst: jest.fn(),
    },
    lancamentoFinanceiro: {
      count: jest.fn().mockResolvedValue(0),
    },
  };
}

describe('ContasService', () => {
  it('lists only the accounts belonging to the given user', async () => {
    const prisma = buildPrismaMock();
    const service = new ContasService(prisma as any);

    await service.list('user-1');

    expect(prisma.contaFinanceira.findMany).toHaveBeenCalledWith({
      where: { userId: 'user-1' },
      orderBy: { criadoEm: 'asc' },
    });
  });

  it('creates an account scoped to the given user', async () => {
    const prisma = buildPrismaMock();
    const service = new ContasService(prisma as any);

    await service.create('user-1', { nome: 'Conta Corrente', tipo: 'CORRENTE', saldoAtual: 100 });

    expect(prisma.contaFinanceira.create).toHaveBeenCalledWith({
      data: { userId: 'user-1', nome: 'Conta Corrente', tipo: 'CORRENTE', saldoAtual: 100, cor: undefined },
    });
  });

  it('refuses to delete an account that has linked lançamentos', async () => {
    const prisma = buildPrismaMock();
    prisma.contaFinanceira.findFirst.mockResolvedValue({ id: 'conta-1', userId: 'user-1' });
    prisma.lancamentoFinanceiro.count.mockResolvedValue(2);
    const service = new ContasService(prisma as any);

    await expect(service.remove('user-1', 'conta-1')).rejects.toThrow();
    expect(prisma.contaFinanceira.delete).not.toHaveBeenCalled();
  });

  it('deletes an account with no linked lançamentos', async () => {
    const prisma = buildPrismaMock();
    prisma.contaFinanceira.findFirst.mockResolvedValue({ id: 'conta-1', userId: 'user-1' });
    const service = new ContasService(prisma as any);

    await service.remove('user-1', 'conta-1');

    expect(prisma.contaFinanceira.delete).toHaveBeenCalledWith({ where: { id: 'conta-1' } });
  });
});
