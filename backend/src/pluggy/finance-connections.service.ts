import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { UsersService } from '../users/users.service';
import { PluggyApiClient } from './pluggy-api-client.service';

@Injectable()
export class FinanceConnectionsService {
  private readonly logger = new Logger(FinanceConnectionsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly usersService: UsersService,
    private readonly pluggyApiClient: PluggyApiClient,
  ) {}

  async createConnectToken(): Promise<{ connectToken: string }> {
    const connectToken = await this.pluggyApiClient.createConnectToken();
    return { connectToken };
  }

  async finalizeConnection(firebaseUid: string, itemId: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const item = await this.pluggyApiClient.getItem(itemId);
    return this.prisma.financeConnection.upsert({
      where: { userId_pluggyItemId: { userId: user.id, pluggyItemId: itemId } },
      update: { status: item.status, instituicao: item.connector.name },
      create: { userId: user.id, pluggyItemId: itemId, instituicao: item.connector.name, status: item.status },
      // Mesma projeção estreita de listConnections: userId/pluggyItemId/criadoEm são internos.
      select: { id: true, instituicao: true, status: true },
    });
  }

  async listConnections(firebaseUid: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    return this.prisma.financeConnection.findMany({
      where: { userId: user.id },
      select: { id: true, instituicao: true, status: true },
    });
  }

  async disconnect(firebaseUid: string, connectionId: string): Promise<void> {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const connection = await this.prisma.financeConnection.findFirst({
      where: { id: connectionId, userId: user.id },
    });
    if (!connection) {
      throw new NotFoundException('Conexão não encontrada.');
    }

    try {
      await this.pluggyApiClient.deleteItem(connection.pluggyItemId);
    } catch (error) {
      // Best-effort, same reasoning as GmailConnectionsService.disconnect: if the item was
      // already removed on Pluggy's side, local cleanup must still proceed.
      this.logger.warn(
        `Failed to delete Pluggy item during disconnect (continuing with local cleanup): ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }

    await this.prisma.financeAccount.deleteMany({ where: { conexaoId: connection.id } });
    await this.prisma.financeConnection.delete({ where: { id: connection.id } });

    const remaining = await this.prisma.financeConnection.count({ where: { userId: user.id } });
    if (remaining === 0) {
      // boletos_dda is keyed by userId, not by connection (DDA boletos aren't tied to one bank),
      // so they only get cleaned up once no connection is left to justify keeping them.
      await this.prisma.boletoDda.deleteMany({ where: { userId: user.id } });
    }
  }
}
