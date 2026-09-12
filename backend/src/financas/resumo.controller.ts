import { Controller, Get, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { PrismaService } from '../prisma/prisma.service';
import { UsersService } from '../users/users.service';
import { BoletoParaCalculo, ContaParaCalculo, SaldoLivreCalculator } from './saldo-livre.calculator';

@UseGuards(FirebaseAuthGuard)
@Controller('financas')
export class ResumoController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly usersService: UsersService,
    private readonly calculator: SaldoLivreCalculator,
  ) {}

  @Get('resumo')
  async getResumo(@CurrentFirebaseUid() firebaseUid: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);

    const [contasRaw, lancamentosRaw] = await Promise.all([
      this.prisma.contaFinanceira.findMany({ where: { userId: user.id } }),
      this.prisma.lancamentoFinanceiro.findMany({ where: { userId: user.id, status: 'CONFIRMADO' } }),
    ]);

    // ContaFinanceira.tipo is always CORRENTE/CARTEIRA/POUPANCA — credit cards
    // are a separate model (CartaoCredito) and never appear here; their open
    // invoices come from FATURA_CARTAO lançamentos below.
    const contas: ContaParaCalculo[] = contasRaw.map((c) => ({
      tipo: c.tipo,
      saldoOuFatura: c.saldoAtual.toNumber(),
    }));

    const faturasAbertas: ContaParaCalculo[] = lancamentosRaw
      .filter((l) => l.tipo === 'FATURA_CARTAO' && l.valor !== null)
      .map((l) => ({ tipo: 'CARTAO_CREDITO', saldoOuFatura: l.valor!.toNumber() }));

    const boletos: BoletoParaCalculo[] = lancamentosRaw
      .filter((l) => l.tipo !== 'FATURA_CARTAO' && l.valor !== null)
      .map((l) => ({ valor: l.valor!.toNumber(), vencimento: l.dataVencimento, pago: l.isPago }));

    const resultado = this.calculator.calcular({
      contas: [...contas, ...faturasAbertas],
      boletos,
      diaRecebimento: user.diaRecebimento,
      hoje: new Date(),
    });

    return {
      saldoLivre: resultado.saldoLivre,
      saldoContas: contas.reduce((sum, c) => sum + c.saldoOuFatura, 0),
      faturasAbertas: faturasAbertas.reduce((sum, c) => sum + c.saldoOuFatura, 0),
      despesasPendentesCiclo: boletos
        .filter((b) => !b.pago && b.vencimento >= resultado.inicioCiclo && b.vencimento <= resultado.fimCiclo)
        .reduce((sum, b) => sum + b.valor, 0),
      cicloFim: resultado.fimCiclo,
    };
  }
}
