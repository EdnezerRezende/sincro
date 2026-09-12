import { SaldoLivreCalculator } from './saldo-livre.calculator';

describe('SaldoLivreCalculator', () => {
  const calculator = new SaldoLivreCalculator();
  const hoje = new Date(2026, 7, 3); // 3 de agosto de 2026, timestamp local (como new Date() no controller)

  it('subtracts open card bills regardless of the cycle window', () => {
    const result = calculator.calcular({
      contas: [
        { tipo: 'CORRENTE', saldoOuFatura: 1000 },
        { tipo: 'CARTAO_CREDITO', saldoOuFatura: 300 },
      ],
      boletos: [],
      diaRecebimento: null,
      hoje,
    });

    expect(result.saldoLivre).toBe(700);
  });

  it('subtracts unpaid boletos due within the cycle, ignoring ones outside it', () => {
    const result = calculator.calcular({
      contas: [{ tipo: 'CORRENTE', saldoOuFatura: 1000 }],
      boletos: [
        { valor: 100, vencimento: new Date(Date.UTC(2026, 7, 5)), pago: false }, // dentro (dia_recebimento=10)
        { valor: 50, vencimento: new Date(Date.UTC(2026, 7, 15)), pago: false }, // fora
        { valor: 999, vencimento: new Date(Date.UTC(2026, 7, 5)), pago: true }, // pago, ignorado
      ],
      diaRecebimento: 10,
      hoje,
    });

    expect(result.saldoLivre).toBe(900);
  });

  it('rolls the cycle to next month when dia_recebimento already passed this month', () => {
    const result = calculator.calcular({
      contas: [],
      boletos: [{ valor: 100, vencimento: new Date(Date.UTC(2026, 8, 1)), pago: false }], // 1º de setembro
      diaRecebimento: 1, // já passou em agosto (hoje = 3 de agosto)
      hoje,
    });

    expect(result.fimCiclo).toEqual(new Date(Date.UTC(2026, 8, 1)));
    expect(result.saldoLivre).toBe(-100);
  });

  it('defaults to the last day of the current month when dia_recebimento is not set', () => {
    const result = calculator.calcular({ contas: [], boletos: [], diaRecebimento: null, hoje });

    expect(result.fimCiclo).toEqual(new Date(Date.UTC(2026, 7, 31)));
  });

  it('clamps dia_recebimento to the last day of shorter months', () => {
    const fevereiro = new Date(2026, 1, 1); // 1º de fevereiro de 2026 (28 dias), timestamp local
    const result = calculator.calcular({ contas: [], boletos: [], diaRecebimento: 31, hoje: fevereiro });

    expect(result.fimCiclo).toEqual(new Date(Date.UTC(2026, 1, 28)));
  });

  it('uses the LOCAL calendar day of "hoje" even with a realistic non-midnight timestamp', () => {
    // hoje é um timestamp real (como o "new Date()" que o controller passa), não um
    // instante UTC-meia-noite. 23:30 local em 3 de agosto de 2026: em fusos atrás de UTC
    // (ex.: America/Sao_Paulo, UTC-3) isso já é madrugada de 4 de agosto em UTC. O ciclo
    // deve continuar refletindo o dia local (3 de agosto), não o dia UTC.
    const hojeNoite = new Date(2026, 7, 3, 23, 30);

    const result = calculator.calcular({
      contas: [],
      boletos: [],
      diaRecebimento: null,
      hoje: hojeNoite,
    });

    expect(result.inicioCiclo).toEqual(new Date(Date.UTC(2026, 7, 3)));
    expect(result.fimCiclo).toEqual(new Date(Date.UTC(2026, 7, 31)));
  });
});
