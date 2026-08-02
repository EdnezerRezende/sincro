import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { UsersService } from '../users/users.service';
import { TokenCryptoService } from '../crypto/token-crypto.service';
import { GmailOAuthService } from './gmail-oauth.service';

@Injectable()
export class GmailConnectionsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly usersService: UsersService,
    private readonly tokenCrypto: TokenCryptoService,
    private readonly oauthService: GmailOAuthService,
  ) {}

  async connect(firebaseUid: string, serverAuthCode: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const { refreshToken } = await this.oauthService.exchangeServerAuthCode(serverAuthCode);
    const gmailEmail = await this.oauthService.getEmailAddress(refreshToken);
    const refreshTokenCriptografado = this.tokenCrypto.encrypt(refreshToken);

    return this.prisma.gmailConnection.upsert({
      where: { userId: user.id },
      update: { refreshTokenCriptografado, gmailEmail },
      create: { userId: user.id, refreshTokenCriptografado, gmailEmail },
    });
  }

  async status(firebaseUid: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const connection = await this.prisma.gmailConnection.findUnique({ where: { userId: user.id } });
    return { connected: connection !== null, gmailEmail: connection?.gmailEmail ?? null };
  }

  async getDecryptedRefreshToken(userId: string): Promise<string | null> {
    const connection = await this.prisma.gmailConnection.findUnique({ where: { userId } });
    if (!connection) return null;
    return this.tokenCrypto.decrypt(connection.refreshTokenCriptografado);
  }

  async disconnect(firebaseUid: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const connection = await this.prisma.gmailConnection.findUnique({ where: { userId: user.id } });
    if (connection) {
      const refreshToken = this.tokenCrypto.decrypt(connection.refreshTokenCriptografado);
      await this.oauthService.revoke(refreshToken);
    }
    await this.prisma.emailSummary.deleteMany({ where: { userId: user.id } });
    await this.prisma.gmailConnection.deleteMany({ where: { userId: user.id } });
  }
}
