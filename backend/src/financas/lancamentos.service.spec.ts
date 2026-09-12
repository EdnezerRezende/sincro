import { LancamentosService } from './lancamentos.service';

function buildDeps() {
  const prisma = {
    lancamentoFinanceiro: {
      findMany: jest.fn().mockResolvedValue([]),
      create: jest.fn().mockResolvedValue({ id: 'lanc-1' }),
      update: jest.fn().mockResolvedValue({ id: 'lanc-1' }),
      findFirst: jest.fn(),
      delete: jest.fn(),
    },
    contaFinanceira: {
      findFirst: jest.fn().mockResolvedValue({ id: 'conta-1', userId: 'user-1' }),
    },
    cartaoCredito: {
      findFirst: jest.fn().mockResolvedValue({ id: 'cartao-1', userId: 'user-1' }),
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

  it('throws when contaId belongs to a different user', async () => {
    const { prisma, service } = buildDeps();
    prisma.contaFinanceira.findFirst.mockResolvedValue(null);

    await expect(
      service.createManual('user-1', {
        tipo: 'DESPESA',
        descricao: 'Mercado',
        dataVencimento: '2026-09-20',
        contaId: 'conta-de-outro-usuario',
      }),
    ).rejects.toThrow();
    expect(prisma.lancamentoFinanceiro.create).not.toHaveBeenCalled();
  });

  it('throws when cartaoId belongs to a different user', async () => {
    const { prisma, service } = buildDeps();
    prisma.cartaoCredito.findFirst.mockResolvedValue(null);

    await expect(
      service.createManual('user-1', {
        tipo: 'FATURA_CARTAO',
        descricao: 'Fatura',
        dataVencimento: '2026-09-20',
        cartaoId: 'cartao-de-outro-usuario',
      }),
    ).rejects.toThrow();
    expect(prisma.lancamentoFinanceiro.create).not.toHaveBeenCalled();
  });
});

describe('LancamentosService — confirmar', () => {
  it('applies the adjustment, sets status CONFIRMADO, and syncs the calendar event', async () => {
    const { prisma, calendarSync, service } = buildDeps();
    prisma.lancamentoFinanceiro.findFirst.mockResolvedValue({
      id: 'lanc-1', userId: 'user-1', status: 'PENDENTE_REVISAO', googleEventId: null,
    });
    prisma.lancamentoFinanceiro.update.mockResolvedValue({
      id: 'lanc-1', status: 'CONFIRMADO', descricao: 'Fatura Nubank', instituicao: 'Nubank',
      valor: 500, dataVencimento: new Date(Date.UTC(2026, 9, 10)), googleEventId: null,
    });
    calendarSync.syncOnConfirm.mockResolvedValue('evt-novo');

    await service.confirmar('user-1', 'lanc-1', { valor: 500 });

    expect(prisma.lancamentoFinanceiro.update).toHaveBeenCalledWith({
      where: { id: 'lanc-1' },
      data: { valor: 500, status: 'CONFIRMADO' },
    });
    expect(calendarSync.syncOnConfirm).toHaveBeenCalled();
    expect(prisma.lancamentoFinanceiro.update).toHaveBeenLastCalledWith({
      where: { id: 'lanc-1' },
      data: { googleEventId: 'evt-novo' },
    });
  });

  it('throws when the lançamento does not belong to the user', async () => {
    const { prisma, service } = buildDeps();
    prisma.lancamentoFinanceiro.findFirst.mockResolvedValue(null);

    await expect(service.confirmar('user-1', 'lanc-x', {})).rejects.toThrow();
  });

  it('throws when confirming with a contaId that belongs to a different user', async () => {
    const { prisma, service } = buildDeps();
    prisma.lancamentoFinanceiro.findFirst.mockResolvedValue({
      id: 'lanc-1', userId: 'user-1', status: 'PENDENTE_REVISAO', googleEventId: null,
    });
    prisma.contaFinanceira.findFirst.mockResolvedValue(null);

    await expect(
      service.confirmar('user-1', 'lanc-1', { contaId: 'conta-de-outro-usuario' }),
    ).rejects.toThrow();
    expect(prisma.lancamentoFinanceiro.update).not.toHaveBeenCalled();
  });
});

describe('LancamentosService — ignorar', () => {
  it('sets status IGNORADO and removes any linked calendar event', async () => {
    const { prisma, calendarSync, service } = buildDeps();
    prisma.lancamentoFinanceiro.findFirst.mockResolvedValue({
      id: 'lanc-1', userId: 'user-1', status: 'PENDENTE_REVISAO', googleEventId: 'evt-1',
    });
    prisma.lancamentoFinanceiro.update.mockResolvedValue({ id: 'lanc-1', status: 'IGNORADO' });

    await service.ignorar('user-1', 'lanc-1');

    expect(prisma.lancamentoFinanceiro.update).toHaveBeenCalledWith({
      where: { id: 'lanc-1' },
      data: { status: 'IGNORADO' },
    });
    expect(calendarSync.removeEvent).toHaveBeenCalledWith('user-1', 'evt-1');
  });
});

describe('LancamentosService — remove', () => {
  it('refuses to delete a CONFIRMADO lançamento', async () => {
    const { prisma, service } = buildDeps();
    prisma.lancamentoFinanceiro.findFirst.mockResolvedValue({ id: 'lanc-1', status: 'CONFIRMADO', googleEventId: null });

    await expect(service.remove('user-1', 'lanc-1')).rejects.toThrow();
  });

  it('deletes a PENDENTE_REVISAO lançamento and removes its calendar event if any', async () => {
    const { prisma, calendarSync, service } = buildDeps();
    prisma.lancamentoFinanceiro.findFirst.mockResolvedValue({ id: 'lanc-1', status: 'PENDENTE_REVISAO', googleEventId: 'evt-1' });
    prisma.lancamentoFinanceiro.delete = jest.fn();

    await service.remove('user-1', 'lanc-1');

    expect(prisma.lancamentoFinanceiro.delete).toHaveBeenCalledWith({ where: { id: 'lanc-1' } });
    expect(calendarSync.removeEvent).toHaveBeenCalledWith('user-1', 'evt-1');
  });
});
