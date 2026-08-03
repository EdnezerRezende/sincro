import { Controller, Get, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { PrismaService } from '../prisma/prisma.service';
import { UsersService } from '../users/users.service';
import { SaldoLivreCalculator } from './saldo-livre.calculator';

// Band-aid até existir um "marcar como pago" de verdade: boletos vencidos há mais de 60 dias
// somem da lista exibida em vez de acumularem para sempre.
const BOLETO_DISPLAY_FLOOR_DAYS = 60;

@UseGuards(FirebaseAuthGuard)
@Controller('financas')
export class FinanceResumoController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly usersService: UsersService,
    private readonly calculator: SaldoLivreCalculator,
  ) {}

  @Get('resumo')
  async getResumo(@CurrentFirebaseUid() firebaseUid: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const connections = await this.prisma.financeConnection.findMany({
      where: { userId: user.id },
      include: { contas: true },
    });
    const contas = connections.flatMap((c) => c.contas);

    // Nada hoje marca um boleto como pago (a Pluggy não expõe status de pagamento consumido),
    // então sem um piso a lista "a vencer" cresceria para sempre, mostrando "venceu há 400
    // dia(s)". Este piso é sobre o que a tela EXIBE. O saldo livre não muda: o calculador já
    // considera apenas boletos do ciclo atual (vencimento >= hoje), que está bem dentro da
    // janela de 60 dias.
    const hoje = new Date();
    const pisoBoletos = new Date(
      Date.UTC(hoje.getFullYear(), hoje.getMonth(), hoje.getDate() - BOLETO_DISPLAY_FLOOR_DAYS),
    );
    const boletos = await this.prisma.boletoDda.findMany({
      where: { userId: user.id, pago: false, vencimento: { gte: pisoBoletos } },
    });

    const resultado = this.calculator.calcular({
      contas: contas.map((c) => ({ tipo: c.tipo, saldoOuFatura: c.saldoOuFatura.toNumber() })),
      boletos: boletos.map((b) => ({ valor: b.valor.toNumber(), vencimento: b.vencimento, pago: b.pago })),
      diaRecebimento: user.diaRecebimento,
      hoje,
    });

    return {
      saldoLivre: resultado.saldoLivre,
      fimCiclo: resultado.fimCiclo,
      contas: contas.map((c) => ({
        id: c.id,
        tipo: c.tipo,
        nome: c.nome,
        saldoOuFatura: c.saldoOuFatura.toNumber(),
        vencimentoFatura: c.vencimentoFatura,
      })),
      boletos: boletos.map((b) => ({ id: b.id, valor: b.valor.toNumber(), vencimento: b.vencimento })),
    };
  }
}
