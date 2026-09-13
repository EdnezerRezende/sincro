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

    // Faturas já pagas pelo usuário não devem continuar sendo subtraídas do
    // Saldo Livre — o mesmo raciocínio já aplicado a DESPESA via `!b.pago`
    // dentro do SaldoLivreCalculator.
    const faturasAbertas: ContaParaCalculo[] = lancamentosRaw
      .filter((l) => l.tipo === 'FATURA_CARTAO' && l.valor !== null && !l.isPago)
      .map((l) => ({ tipo: 'CARTAO_CREDITO', saldoOuFatura: l.valor!.toNumber() }));

    const boletos: BoletoParaCalculo[] = lancamentosRaw
      .filter((l) => l.tipo === 'DESPESA' && l.valor !== null)
      .map((l) => ({ valor: l.valor!.toNumber(), vencimento: l.dataVencimento, pago: l.isPago }));

    // RECEITA só entra no Saldo Livre quando o usuário confirma que o dinheiro
    // já foi de fato recebido (isPago=true) — receita esperada mas ainda não
    // recebida não é somada, para não inflar artificialmente o saldo com
    // dinheiro que ainda não está disponível.
    const receitasRecebidas = lancamentosRaw
      .filter((l) => l.tipo === 'RECEITA' && l.valor !== null && l.isPago)
      .reduce((sum, l) => sum + l.valor!.toNumber(), 0);

    const resultado = this.calculator.calcular({
      contas: [...contas, ...faturasAbertas],
      boletos,
      diaRecebimento: user.diaRecebimento,
      hoje: new Date(),
    });

    return {
      saldoLivre: resultado.saldoLivre + receitasRecebidas,
      saldoContas: contas.reduce((sum, c) => sum + c.saldoOuFatura, 0),
      faturasAbertas: faturasAbertas.reduce((sum, c) => sum + c.saldoOuFatura, 0),
      despesasPendentesCiclo: boletos
        .filter((b) => !b.pago && b.vencimento >= resultado.inicioCiclo && b.vencimento <= resultado.fimCiclo)
        .reduce((sum, b) => sum + b.valor, 0),
      cicloFim: resultado.fimCiclo,
    };
  }
}
