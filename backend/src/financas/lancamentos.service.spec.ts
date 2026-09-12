import { LancamentosService } from './lancamentos.service';

function buildDeps() {
  const prisma = {
    lancamentoFinanceiro: {
      findMany: jest.fn().mockResolvedValue([]),
      create: jest.fn().mockResolvedValue({ id: 'lanc-1' }),
      update: jest.fn().mockResolvedValue({ id: 'lanc-1' }),
      findFirst: jest.fn(),
    },
  };
  const calendarSync = { syncOnConfirm: jest.fn(), removeEvent: jest.fn() };
  return { prisma, calendarSync, service: new LancamentosService(prisma as any, calendarSync as any) };
}

describe('LancamentosService — list', () => {
  it('filters by status and by month of dataVencimento', async () => {
    const { prisma, service } = buildDeps();

    await service.list('user-1', { status: 'PENDENTE_REVISAO', mes: '2026-09' });

    expect(prisma.lancamentoFinanceiro.findMany).toHaveBeenCalledWith({
      where: {
        userId: 'user-1',
        status: 'PENDENTE_REVISAO',
        dataVencimento: {
          gte: new Date(Date.UTC(2026, 8, 1)),
          lt: new Date(Date.UTC(2026, 9, 1)),
        },
      },
      orderBy: { dataVencimento: 'asc' },
    });
  });

  it('lists everything for the user when no filters are given', async () => {
    const { prisma, service } = buildDeps();

    await service.list('user-1', {});

    expect(prisma.lancamentoFinanceiro.findMany).toHaveBeenCalledWith({
      where: { userId: 'user-1' },
      orderBy: { dataVencimento: 'asc' },
    });
  });
});

describe('LancamentosService — createManual', () => {
  it('creates a lançamento already CONFIRMADO with origem MANUAL', async () => {
    const { prisma, service } = buildDeps();

    await service.createManual('user-1', {
      tipo: 'DESPESA',
      descricao: 'Mercado',
      dataVencimento: '2026-09-20',
    });

    expect(prisma.lancamentoFinanceiro.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        userId: 'user-1',
        tipo: 'DESPESA',
        descricao: 'Mercado',
        status: 'CONFIRMADO',
        origem: 'MANUAL',
        dataVencimento: new Date('2026-09-20'),
        dataCompetencia: new Date('2026-09-20'),
      }),
    });
  });
});
