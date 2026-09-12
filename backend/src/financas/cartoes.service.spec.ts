import { CartoesService } from './cartoes.service';

function buildPrismaMock() {
  return {
    cartaoCredito: {
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

describe('CartoesService', () => {
  it('lists only the cards belonging to the given user', async () => {
    const prisma = buildPrismaMock();
    const service = new CartoesService(prisma as any);

    await service.list('user-1');

    expect(prisma.cartaoCredito.findMany).toHaveBeenCalledWith({
      where: { userId: 'user-1' },
      orderBy: { criadoEm: 'asc' },
    });
  });

  it('creates a card scoped to the given user', async () => {
    const prisma = buildPrismaMock();
    const service = new CartoesService(prisma as any);

    await service.create('user-1', {
      nome: 'Nubank',
      diaFechamento: 10,
      diaVencimento: 17,
      limiteTotal: 5000,
    });

    expect(prisma.cartaoCredito.create).toHaveBeenCalledWith({
      data: {
        userId: 'user-1',
        nome: 'Nubank',
        diaFechamento: 10,
        diaVencimento: 17,
        limiteTotal: 5000,
        cor: undefined,
      },
    });
  });

  it('refuses to delete a card that has linked lançamentos', async () => {
    const prisma = buildPrismaMock();
    prisma.lancamentoFinanceiro.count.mockResolvedValue(1);
    const service = new CartoesService(prisma as any);

    await expect(service.remove('user-1', 'cartao-1')).rejects.toThrow();
  });
});
