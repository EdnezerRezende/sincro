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
  const calendarSync = {
    syncOnConfirm: jest.fn().mockResolvedValue(null),
    removeEvent: jest.fn().mockResolvedValue(true),
  };
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
    prisma.lancamentoFinanceiro.create.mockResolvedValue({
      id: 'lanc-1', tipo: 'DESPESA', status: 'CONFIRMADO', isPago: false, googleEventId: null,
    });

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

  it('syncs a calendar event for a manually created DESPESA not yet paid', async () => {
    const { prisma, calendarSync, service } = buildDeps();
    const criado = { id: 'lanc-1', tipo: 'DESPESA', status: 'CONFIRMADO', isPago: false, googleEventId: null };
    prisma.lancamentoFinanceiro.create.mockResolvedValue(criado);
    calendarSync.syncOnConfirm.mockResolvedValue('evt-novo');

    await service.createManual('user-1', { tipo: 'DESPESA', descricao: 'Mercado', dataVencimento: '2026-09-20' });

    expect(calendarSync.syncOnConfirm).toHaveBeenCalledWith('user-1', criado);
    expect(prisma.lancamentoFinanceiro.update).toHaveBeenCalledWith({
      where: { id: 'lanc-1' },
      data: { googleEventId: 'evt-novo' },
    });
  });

  it('never syncs a calendar event for a manually created RECEITA', async () => {
    const { prisma, calendarSync, service } = buildDeps();
    prisma.lancamentoFinanceiro.create.mockResolvedValue({
      id: 'lanc-1', tipo: 'RECEITA', status: 'CONFIRMADO', isPago: false, googleEventId: null,
    });

    await service.createManual('user-1', { tipo: 'RECEITA', descricao: 'Salário', dataVencimento: '2026-09-20' });

    expect(calendarSync.syncOnConfirm).not.toHaveBeenCalled();
    expect(prisma.lancamentoFinanceiro.update).not.toHaveBeenCalled();
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
  it('applies the adjustment, sets status CONFIRMADO, and syncs the calendar event for an unpaid DESPESA', async () => {
    const { prisma, calendarSync, service } = buildDeps();
    prisma.lancamentoFinanceiro.findFirst.mockResolvedValue({
      id: 'lanc-1', userId: 'user-1', status: 'PENDENTE_REVISAO', googleEventId: null,
    });
    prisma.lancamentoFinanceiro.update.mockResolvedValue({
      id: 'lanc-1', tipo: 'DESPESA', status: 'CONFIRMADO', isPago: false, descricao: 'Fatura Nubank',
      instituicao: 'Nubank', valor: 500, dataVencimento: new Date(Date.UTC(2026, 9, 10)), googleEventId: null,
    });
    calendarSync.syncOnConfirm.mockResolvedValue('evt-novo');

    await service.confirmar('user-1', 'lanc-1', { valor: 500 });

    expect(prisma.lancamentoFinanceiro.update).toHaveBeenNthCalledWith(1, {
      where: { id: 'lanc-1' },
      data: { valor: 500, status: 'CONFIRMADO' },
    });
    expect(calendarSync.syncOnConfirm).toHaveBeenCalled();
    expect(prisma.lancamentoFinanceiro.update).toHaveBeenNthCalledWith(2, {
      where: { id: 'lanc-1' },
      data: { googleEventId: 'evt-novo' },
    });
  });

  it('confirming a RECEITA never syncs a calendar event', async () => {
    const { prisma, calendarSync, service } = buildDeps();
    prisma.lancamentoFinanceiro.findFirst.mockResolvedValue({
      id: 'lanc-1', userId: 'user-1', status: 'PENDENTE_REVISAO', googleEventId: null,
    });
    prisma.lancamentoFinanceiro.update.mockResolvedValue({
      id: 'lanc-1', tipo: 'RECEITA', status: 'CONFIRMADO', isPago: false, googleEventId: null,
    });

    await service.confirmar('user-1', 'lanc-1', {});

    expect(calendarSync.syncOnConfirm).not.toHaveBeenCalled();
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

describe('LancamentosService — update', () => {
  it('syncs the calendar event when the DESPESA stays CONFIRMADO and unpaid', async () => {
    const { prisma, calendarSync, service } = buildDeps();
    prisma.lancamentoFinanceiro.findFirst.mockResolvedValue({
      id: 'lanc-1', userId: 'user-1', status: 'CONFIRMADO', googleEventId: null,
    });
    prisma.lancamentoFinanceiro.update.mockResolvedValue({
      id: 'lanc-1', tipo: 'DESPESA', status: 'CONFIRMADO', isPago: false, googleEventId: null,
    });
    calendarSync.syncOnConfirm.mockResolvedValue('evt-1');

    await service.update('user-1', 'lanc-1', { descricao: 'Mercado (editado)' });

    expect(calendarSync.syncOnConfirm).toHaveBeenCalled();
    expect(prisma.lancamentoFinanceiro.update).toHaveBeenLastCalledWith({
      where: { id: 'lanc-1' },
      data: { googleEventId: 'evt-1' },
    });
  });

  it('removes the calendar event and clears googleEventId when isPago becomes true', async () => {
    const { prisma, calendarSync, service } = buildDeps();
    prisma.lancamentoFinanceiro.findFirst.mockResolvedValue({
      id: 'lanc-1', userId: 'user-1', status: 'CONFIRMADO', googleEventId: 'evt-existente',
    });
    prisma.lancamentoFinanceiro.update.mockResolvedValue({
      id: 'lanc-1', tipo: 'DESPESA', status: 'CONFIRMADO', isPago: true, googleEventId: 'evt-existente',
    });

    await service.update('user-1', 'lanc-1', { isPago: true });

    expect(calendarSync.removeEvent).toHaveBeenCalledWith('user-1', 'evt-existente');
    expect(calendarSync.syncOnConfirm).not.toHaveBeenCalled();
    expect(prisma.lancamentoFinanceiro.update).toHaveBeenLastCalledWith({
      where: { id: 'lanc-1' },
      data: { googleEventId: null },
    });
  });

  it('keeps googleEventId when isPago becomes true but the calendar removal could not be confirmed', async () => {
    const { prisma, calendarSync, service } = buildDeps();
    calendarSync.removeEvent.mockResolvedValue(false);
    prisma.lancamentoFinanceiro.findFirst.mockResolvedValue({
      id: 'lanc-1', userId: 'user-1', status: 'CONFIRMADO', googleEventId: 'evt-existente',
    });
    prisma.lancamentoFinanceiro.update.mockResolvedValue({
      id: 'lanc-1', tipo: 'DESPESA', status: 'CONFIRMADO', isPago: true, googleEventId: 'evt-existente',
    });

    await service.update('user-1', 'lanc-1', { isPago: true });

    expect(calendarSync.removeEvent).toHaveBeenCalledWith('user-1', 'evt-existente');
    // Não confirma remoção no Google Calendar -> não limpa googleEventId, para tentar de novo depois.
    expect(prisma.lancamentoFinanceiro.update).toHaveBeenCalledTimes(1); // só a atualização principal
  });

  it('does nothing to the calendar when isPago becomes true but there was no event yet', async () => {
    const { prisma, calendarSync, service } = buildDeps();
    prisma.lancamentoFinanceiro.findFirst.mockResolvedValue({
      id: 'lanc-1', userId: 'user-1', status: 'CONFIRMADO', googleEventId: null,
    });
    prisma.lancamentoFinanceiro.update.mockResolvedValue({
      id: 'lanc-1', tipo: 'DESPESA', status: 'CONFIRMADO', isPago: true, googleEventId: null,
    });

    await service.update('user-1', 'lanc-1', { isPago: true });

    expect(calendarSync.removeEvent).not.toHaveBeenCalled();
    expect(prisma.lancamentoFinanceiro.update).toHaveBeenCalledTimes(1); // só a atualização principal
  });

  it('never syncs a RECEITA even when CONFIRMADO and unpaid', async () => {
    const { prisma, calendarSync, service } = buildDeps();
    prisma.lancamentoFinanceiro.findFirst.mockResolvedValue({
      id: 'lanc-1', userId: 'user-1', status: 'CONFIRMADO', googleEventId: null,
    });
    prisma.lancamentoFinanceiro.update.mockResolvedValue({
      id: 'lanc-1', tipo: 'RECEITA', status: 'CONFIRMADO', isPago: false, googleEventId: null,
    });

    await service.update('user-1', 'lanc-1', { valor: 999 });

    expect(calendarSync.syncOnConfirm).not.toHaveBeenCalled();
    expect(calendarSync.removeEvent).not.toHaveBeenCalled();
  });

  it('does nothing to the calendar when the lançamento is still PENDENTE_REVISAO', async () => {
    const { prisma, calendarSync, service } = buildDeps();
    prisma.lancamentoFinanceiro.findFirst.mockResolvedValue({
      id: 'lanc-1', userId: 'user-1', status: 'PENDENTE_REVISAO', googleEventId: null,
    });
    prisma.lancamentoFinanceiro.update.mockResolvedValue({
      id: 'lanc-1', tipo: 'DESPESA', status: 'PENDENTE_REVISAO', isPago: false, googleEventId: null,
    });

    await service.update('user-1', 'lanc-1', { descricao: 'ajuste' });

    expect(calendarSync.syncOnConfirm).not.toHaveBeenCalled();
    expect(calendarSync.removeEvent).not.toHaveBeenCalled();
  });

  it('throws when updating with a cartaoId that belongs to a different user', async () => {
    const { prisma, service } = buildDeps();
    prisma.lancamentoFinanceiro.findFirst.mockResolvedValue({
      id: 'lanc-1', userId: 'user-1', status: 'CONFIRMADO', googleEventId: null,
    });
    prisma.cartaoCredito.findFirst.mockResolvedValue(null);

    await expect(
      service.update('user-1', 'lanc-1', { cartaoId: 'cartao-de-outro-usuario' }),
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
  it('deletes a CONFIRMADO lançamento too (users need to be able to undo manual entries)', async () => {
    const { prisma, calendarSync, service } = buildDeps();
    prisma.lancamentoFinanceiro.findFirst.mockResolvedValue({ id: 'lanc-1', status: 'CONFIRMADO', googleEventId: 'evt-2' });
    prisma.lancamentoFinanceiro.delete = jest.fn();

    await service.remove('user-1', 'lanc-1');

    expect(prisma.lancamentoFinanceiro.delete).toHaveBeenCalledWith({ where: { id: 'lanc-1' } });
    expect(calendarSync.removeEvent).toHaveBeenCalledWith('user-1', 'evt-2');
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
