import { ResumoController } from './resumo.controller';
import { SaldoLivreCalculator } from './saldo-livre.calculator';

function decimal(value: number) {
  return { toNumber: () => value };
}

function buildDeps() {
  const prisma = {
    contaFinanceira: { findMany: jest.fn().mockResolvedValue([]) },
    lancamentoFinanceiro: { findMany: jest.fn().mockResolvedValue([]) },
  };
  const usersService = {
    getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'user-1', diaRecebimento: null }),
  };
  return { prisma, usersService, calculator: new SaldoLivreCalculator() };
}

describe('ResumoController', () => {
  it('only feeds CONFIRMADO lançamentos into the calculator', async () => {
    const { prisma, usersService, calculator } = buildDeps();
    const controller = new ResumoController(prisma as any, usersService as any, calculator);

    await controller.getResumo('firebase-uid-1');

    expect(prisma.lancamentoFinanceiro.findMany).toHaveBeenCalledWith({
      where: { userId: 'user-1', status: 'CONFIRMADO' },
    });
  });

  it('excludes a CONFIRMADO lançamento with a null valor from the calculation', async () => {
    jest.useFakeTimers().setSystemTime(new Date(2026, 8, 3));
    try {
      const { prisma, usersService, calculator } = buildDeps();
      prisma.contaFinanceira.findMany.mockResolvedValue([
        { id: 'conta-1', tipo: 'CORRENTE', saldoAtual: decimal(1000) },
      ]);
      prisma.lancamentoFinanceiro.findMany.mockResolvedValue([
        {
          id: 'lanc-1', tipo: 'DESPESA', valor: null, cartaoId: null,
          dataVencimento: new Date(2026, 8, 10), isPago: false,
        },
      ]);
      const controller = new ResumoController(prisma as any, usersService as any, calculator);

      const resumo = await controller.getResumo('firebase-uid-1');

      expect(resumo.saldoLivre).toBe(1000);
    } finally {
      jest.useRealTimers();
    }
  });

  it('does not subtract a CONFIRMADO RECEITA lançamento from saldoLivre', async () => {
    jest.useFakeTimers().setSystemTime(new Date(2026, 8, 3));
    try {
      const { prisma, usersService, calculator } = buildDeps();
      prisma.contaFinanceira.findMany.mockResolvedValue([
        { id: 'conta-1', tipo: 'CORRENTE', saldoAtual: decimal(1000) },
      ]);
      prisma.lancamentoFinanceiro.findMany.mockResolvedValue([
        {
          id: 'lanc-1', tipo: 'RECEITA', valor: decimal(500), cartaoId: null,
          dataVencimento: new Date(2026, 8, 10), isPago: false,
        },
      ]);
      const controller = new ResumoController(prisma as any, usersService as any, calculator);

      const resumo = await controller.getResumo('firebase-uid-1');

      expect(resumo.saldoLivre).toBe(1000);
    } finally {
      jest.useRealTimers();
    }
  });

  it('subtracts an open FATURA_CARTAO within the cycle', async () => {
    jest.useFakeTimers().setSystemTime(new Date(2026, 8, 3));
    try {
      const { prisma, usersService, calculator } = buildDeps();
      prisma.contaFinanceira.findMany.mockResolvedValue([
        { id: 'conta-1', tipo: 'CORRENTE', saldoAtual: decimal(1000) },
      ]);
      prisma.lancamentoFinanceiro.findMany.mockResolvedValue([
        {
          id: 'lanc-1', tipo: 'FATURA_CARTAO', valor: decimal(300), cartaoId: 'cartao-1',
          dataVencimento: new Date(2026, 8, 15), isPago: false,
        },
      ]);
      const controller = new ResumoController(prisma as any, usersService as any, calculator);

      const resumo = await controller.getResumo('firebase-uid-1');

      expect(resumo.saldoLivre).toBe(700);
    } finally {
      jest.useRealTimers();
    }
  });
});
