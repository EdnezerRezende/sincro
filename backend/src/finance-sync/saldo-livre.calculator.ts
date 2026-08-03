import { Injectable } from '@nestjs/common';

export interface ContaParaCalculo {
  tipo: string;
  saldoOuFatura: number;
}

export interface BoletoParaCalculo {
  valor: number;
  vencimento: Date;
  pago: boolean;
}

export interface SaldoLivreResult {
  saldoLivre: number;
  inicioCiclo: Date;
  fimCiclo: Date;
}

@Injectable()
export class SaldoLivreCalculator {
  calcular(params: {
    contas: ContaParaCalculo[];
    boletos: BoletoParaCalculo[];
    diaRecebimento: number | null;
    hoje: Date;
  }): SaldoLivreResult {
    const { contas, boletos, diaRecebimento, hoje } = params;
    const inicioCiclo = this.startOfDay(hoje);
    const fimCiclo = this.calcularFimCiclo(diaRecebimento, hoje);

    const saldoContas = this.somar(contas.filter((c) => c.tipo !== 'CARTAO_CREDITO'));
    const faturasAbertas = this.somar(contas.filter((c) => c.tipo === 'CARTAO_CREDITO'));
    const boletosNoCiclo = boletos
      .filter(
        (b) =>
          !b.pago &&
          b.vencimento.getTime() >= inicioCiclo.getTime() &&
          b.vencimento.getTime() <= fimCiclo.getTime(),
      )
      .reduce((sum, b) => sum + b.valor, 0);

    return { saldoLivre: saldoContas - faturasAbertas - boletosNoCiclo, inicioCiclo, fimCiclo };
  }

  private somar(contas: ContaParaCalculo[]): number {
    return contas.reduce((sum, c) => sum + c.saldoOuFatura, 0);
  }

  private calcularFimCiclo(diaRecebimento: number | null, hoje: Date): Date {
    if (diaRecebimento === null) {
      return new Date(Date.UTC(hoje.getUTCFullYear(), hoje.getUTCMonth() + 1, 0));
    }
    const esteMs = this.diaClampeado(hoje.getUTCFullYear(), hoje.getUTCMonth(), diaRecebimento);
    if (esteMs.getTime() >= this.startOfDay(hoje).getTime()) {
      return esteMs;
    }
    return this.diaClampeado(hoje.getUTCFullYear(), hoje.getUTCMonth() + 1, diaRecebimento);
  }

  private diaClampeado(year: number, month: number, dia: number): Date {
    const ultimoDiaDoMes = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
    return new Date(Date.UTC(year, month, Math.min(dia, ultimoDiaDoMes)));
  }

  private startOfDay(date: Date): Date {
    return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  }
}
