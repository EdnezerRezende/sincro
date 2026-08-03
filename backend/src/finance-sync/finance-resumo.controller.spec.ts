import { FinanceResumoController } from './finance-resumo.controller';
import { SaldoLivreCalculator } from './saldo-livre.calculator';

function decimal(value: number) {
  return { toNumber: () => value };
}

function buildDeps() {
  const prisma = {
    financeConnection: { findMany: jest.fn().mockResolvedValue([]) },
    boletoDda: { findMany: jest.fn().mockResolvedValue([]) },
  };
  const usersService = {
    getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1', diaRecebimento: null }),
  };
  return { prisma, usersService, calculator: new SaldoLivreCalculator() };
}

describe('FinanceResumoController', () => {
  it('applies a 60-day floor so long-overdue boletos age out of the display list', async () => {
    // `boletos_dda.pago` nunca é escrito (a Pluggy não expõe status de pagamento consumido),
    // então sem um piso a lista "a vencer" cresceria para sempre mostrando
    // "venceu há 400 dia(s)".
    jest.useFakeTimers().setSystemTime(new Date(2026, 7, 3, 10, 0));
    try {
      const { prisma, usersService, calculator } = buildDeps();
      const controller = new FinanceResumoController(prisma as any, usersService as any, calculator);

      await controller.getResumo('fb1');

      expect(prisma.boletoDda.findMany).toHaveBeenCalledWith({
        where: {
          userId: 'u1',
          pago: false,
          vencimento: { gte: new Date(Date.UTC(2026, 5, 4)) },
        },
      });
    } finally {
      jest.useRealTimers();
    }
  });

  it('returns boletos that are within the floor window', async () => {
    jest.useFakeTimers().setSystemTime(new Date(2026, 7, 3, 10, 0));
    try {
      const { prisma, usersService, calculator } = buildDeps();
      prisma.boletoDda.findMany.mockResolvedValue([
        { id: 'b-recente', valor: decimal(100), vencimento: new Date(Date.UTC(2026, 7, 5)), pago: false },
      ]);
      const controller = new FinanceResumoController(prisma as any, usersService as any, calculator);

      const resumo = await controller.getResumo('fb1');

      expect(resumo.boletos).toEqual([
        { id: 'b-recente', valor: 100, vencimento: new Date(Date.UTC(2026, 7, 5)) },
      ]);
      // Boleto dentro do ciclo continua descontado do saldo livre.
      expect(resumo.saldoLivre).toBe(-100);
    } finally {
      jest.useRealTimers();
    }
  });
});
