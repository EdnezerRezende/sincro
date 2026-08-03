import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { UsersService } from '../users/users.service';
import { PluggyApiClient } from '../pluggy/pluggy-api-client.service';

@Injectable()
export class FinanceSyncService {
  private readonly logger = new Logger(FinanceSyncService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly pluggyApiClient: PluggyApiClient,
    private readonly usersService: UsersService,
  ) {}

  async syncConnection(connectionId: string): Promise<void> {
    const connection = await this.prisma.financeConnection.findUnique({ where: { id: connectionId } });
    if (!connection) {
      this.logger.warn(`syncConnection called for unknown connection ${connectionId}`);
      return;
    }

    const accounts = await this.pluggyApiClient.listAccounts(connection.pluggyItemId);
    for (const account of accounts) {
      const tipo = account.type === 'CREDIT' ? 'CARTAO_CREDITO' : 'CORRENTE';
      const vencimentoFatura = account.creditData?.balanceCloseDate
        ? new Date(account.creditData.balanceCloseDate)
        : null;
      await this.prisma.financeAccount.upsert({
        where: { conexaoId_pluggyAccountId: { conexaoId: connection.id, pluggyAccountId: account.id } },
        update: { nome: account.name, saldoOuFatura: account.balance, vencimentoFatura },
        create: {
          conexaoId: connection.id,
          pluggyAccountId: account.id,
          tipo,
          nome: account.name,
          saldoOuFatura: account.balance,
          vencimentoFatura,
        },
      });
    }

    const boletos = await this.pluggyApiClient.listBoletos(connection.pluggyItemId);
    for (const boleto of boletos) {
      const vencimento = new Date(boleto.vencimento);
      await this.prisma.boletoDda.upsert({
        where: { userId_codigoBarras: { userId: connection.userId, codigoBarras: boleto.codigoBarras } },
        update: { valor: boleto.valor, vencimento },
        create: { userId: connection.userId, codigoBarras: boleto.codigoBarras, valor: boleto.valor, vencimento },
      });
    }
  }

  async syncAllForUser(firebaseUid: string): Promise<void> {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const connections = await this.prisma.financeConnection.findMany({
      where: { userId: user.id },
      select: { id: true },
    });
    for (const { id } of connections) {
      await this.syncConnection(id);
    }
  }
}
