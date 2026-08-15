import { ForbiddenException, Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { UsersService } from '../users/users.service';
import { TokenCryptoService } from '../crypto/token-crypto.service';
import { GmailOAuthService } from './gmail-oauth.service';

const GMAIL_SEND_SCOPE = 'https://www.googleapis.com/auth/gmail.send';
const CALENDAR_EVENTS_SCOPE = 'https://www.googleapis.com/auth/calendar.events';

@Injectable()
export class GmailConnectionsService {
  private readonly logger = new Logger(GmailConnectionsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly usersService: UsersService,
    private readonly tokenCrypto: TokenCryptoService,
    private readonly oauthService: GmailOAuthService,
  ) {}

  async connect(firebaseUid: string, serverAuthCode: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const { refreshToken, scope } = await this.oauthService.exchangeServerAuthCode(serverAuthCode);
    const gmailEmail = await this.oauthService.getEmailAddress(refreshToken);
    const refreshTokenCriptografado = this.tokenCrypto.encrypt(refreshToken);
    const scopesConcedidos = scope.split(' ');
    const temEscopoEnvio = scopesConcedidos.includes(GMAIL_SEND_SCOPE);
    const temEscopoAgenda = scopesConcedidos.includes(CALENDAR_EVENTS_SCOPE);

    return this.prisma.gmailConnection.upsert({
      where: { userId: user.id },
      update: { refreshTokenCriptografado, gmailEmail, temEscopoEnvio, temEscopoAgenda },
      create: { userId: user.id, refreshTokenCriptografado, gmailEmail, temEscopoEnvio, temEscopoAgenda },
    });
  }

  async status(firebaseUid: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const connection = await this.prisma.gmailConnection.findUnique({ where: { userId: user.id } });
    return {
      connected: connection !== null,
      gmailEmail: connection?.gmailEmail ?? null,
      temEscopoEnvio: connection?.temEscopoEnvio ?? false,
      temEscopoAgenda: connection?.temEscopoAgenda ?? false,
    };
  }

  async getDecryptedRefreshToken(userId: string): Promise<string | null> {
    const connection = await this.prisma.gmailConnection.findUnique({ where: { userId } });
    if (!connection) return null;
    return this.tokenCrypto.decrypt(connection.refreshTokenCriptografado);
  }

  /** Used by endpoints that require a connection to exist before doing anything else (drafting,
   *  sending, confirming a calendar event) — throws instead of returning null so those call sites
   *  don't each have to repeat the same null-check/403 boilerplate. */
  async getConnectionOrThrow(userId: string) {
    const connection = await this.prisma.gmailConnection.findUnique({ where: { userId } });
    if (!connection) {
      throw new ForbiddenException('Gmail não conectado.');
    }
    return connection;
  }

  async disconnect(firebaseUid: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const connection = await this.prisma.gmailConnection.findUnique({ where: { userId: user.id } });
    if (connection) {
      const refreshToken = this.tokenCrypto.decrypt(connection.refreshTokenCriptografado);
      try {
        await this.oauthService.revoke(refreshToken);
      } catch (error) {
        this.logger.warn(
          `Failed to revoke Gmail refresh token with Google during disconnect (continuing with local cleanup): ${
            error instanceof Error ? error.message : String(error)
          }`,
        );
      }
    }
    await this.prisma.emailSummary.deleteMany({ where: { userId: user.id } });
    await this.prisma.gmailConnection.deleteMany({ where: { userId: user.id } });
  }
}
