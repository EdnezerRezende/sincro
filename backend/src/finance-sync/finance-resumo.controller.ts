import { Controller, Get, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { PrismaService } from '../prisma/prisma.service';
import { UsersService } from '../users/users.service';
import { SaldoLivreCalculator } from './saldo-livre.calculator';

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
    const boletos = await this.prisma.boletoDda.findMany({ where: { userId: user.id, pago: false } });

    const resultado = this.calculator.calcular({
      contas: contas.map((c) => ({ tipo: c.tipo, saldoOuFatura: c.saldoOuFatura.toNumber() })),
      boletos: boletos.map((b) => ({ valor: b.valor.toNumber(), vencimento: b.vencimento, pago: b.pago })),
      diaRecebimento: user.diaRecebimento,
      hoje: new Date(),
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
