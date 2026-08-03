import { FinanceAlertScheduler } from './finance-alert.scheduler';

function buildDeps() {
  const prisma = {
    boletoDda: { findMany: jest.fn().mockResolvedValue([]), updateMany: jest.fn() },
    financeAccount: { findMany: jest.fn().mockResolvedValue([]), updateMany: jest.fn() },
  };
  const notificationService = { notifyContasVencendo: jest.fn().mockResolvedValue(undefined) };
  return { prisma, notificationService };
}

describe('FinanceAlertScheduler', () => {
  it('sends one aggregated notification per user combining boletos and faturas', async () => {
    const { prisma, notificationService } = buildDeps();
    prisma.boletoDda.findMany.mockResolvedValue([{ id: 'boleto-1', userId: 'u1' }]);
    prisma.financeAccount.findMany.mockResolvedValue([
      { id: 'fatura-1', conexao: { userId: 'u1' } },
      { id: 'fatura-2', conexao: { userId: 'u2' } },
    ]);
    const scheduler = new FinanceAlertScheduler(prisma as any, notificationService as any);

    await scheduler.checkContasVencendo();

    expect(notificationService.notifyContasVencendo).toHaveBeenCalledWith('u1', 2);
    expect(notificationService.notifyContasVencendo).toHaveBeenCalledWith('u2', 1);
    expect(prisma.boletoDda.updateMany).toHaveBeenCalledWith({
      where: { id: { in: ['boleto-1'] } },
      data: { notificadoEm: expect.any(Date) },
    });
    expect(prisma.financeAccount.updateMany).toHaveBeenCalledWith({
      where: { id: { in: ['fatura-1'] } },
      data: { notificadoEm: expect.any(Date) },
    });
  });

  it('only queries items with notificadoEm still null and vencimento within 3 days', async () => {
    const { prisma, notificationService } = buildDeps();
    const scheduler = new FinanceAlertScheduler(prisma as any, notificationService as any);

    await scheduler.checkContasVencendo();

    expect(prisma.boletoDda.findMany).toHaveBeenCalledWith({
      where: { pago: false, notificadoEm: null, vencimento: { lte: expect.any(Date) } },
    });
    expect(prisma.financeAccount.findMany).toHaveBeenCalledWith({
      where: { tipo: 'CARTAO_CREDITO', notificadoEm: null, vencimentoFatura: { lte: expect.any(Date) } },
      include: { conexao: true },
    });
  });

  it('does not let a failed notification for one user block the others', async () => {
    const { prisma, notificationService } = buildDeps();
    prisma.boletoDda.findMany.mockResolvedValue([
      { id: 'boleto-1', userId: 'u1' },
      { id: 'boleto-2', userId: 'u2' },
    ]);
    notificationService.notifyContasVencendo.mockRejectedValueOnce(new Error('fcm down'));
    const scheduler = new FinanceAlertScheduler(prisma as any, notificationService as any);

    await expect(scheduler.checkContasVencendo()).resolves.not.toThrow();
    expect(notificationService.notifyContasVencendo).toHaveBeenCalledTimes(2);
  });
});
