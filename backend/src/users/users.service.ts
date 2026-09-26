import { forwardRef, Inject, Injectable, Logger, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { FIREBASE_ADMIN } from '../auth/firebase-admin.provider';
import type { FirebaseAdmin } from '../auth/firebase-admin.provider';
import { GmailConnectionsService } from '../gmail/gmail-connections.service';
import { FeatureFlags, resolveFeatureFlags } from './feature-flags';

@Injectable()
export class UsersService {
  private readonly logger = new Logger(UsersService.name);

  constructor(
    private readonly prisma: PrismaService,
    @Inject(forwardRef(() => GmailConnectionsService))
    private readonly gmailConnectionsService: GmailConnectionsService,
    @Inject(FIREBASE_ADMIN) private readonly firebaseAdmin: FirebaseAdmin,
  ) {}

  async upsertByFirebaseUid(firebaseUid: string, nome: string) {
    return this.prisma.user.upsert({
      where: { firebaseUid },
      update: { nome },
      create: { firebaseUid, nome },
    });
  }

  async getByFirebaseUidOrThrow(firebaseUid: string) {
    const user = await this.prisma.user.findUnique({ where: { firebaseUid } });
    if (!user) {
      throw new NotFoundException('Usuário ainda não completou o cadastro inicial');
    }
    return user;
  }

  async getOnboardingStatus(firebaseUid: string) {
    const user = await this.getByFirebaseUidOrThrow(firebaseUid);
    const [sensoryProfile, trustedContactCount] = await Promise.all([
      this.prisma.sensoryProfile.findUnique({ where: { userId: user.id } }),
      this.prisma.trustedContact.count({ where: { userId: user.id } }),
    ]);

    return {
      userId: user.id,
      nome: user.nome,
      hasSensoryProfile: sensoryProfile !== null,
      trustedContactCount,
      diaRecebimento: user.diaRecebimento,
      isAdmin: user.isAdmin,
    };
  }

  async registerFcmToken(firebaseUid: string, fcmToken: string): Promise<void> {
    const user = await this.getByFirebaseUidOrThrow(firebaseUid);
    await this.prisma.user.update({ where: { id: user.id }, data: { fcmToken } });
  }

  async updateDiaRecebimento(firebaseUid: string, diaRecebimento: number | null): Promise<void> {
    const user = await this.getByFirebaseUidOrThrow(firebaseUid);
    await this.prisma.user.update({ where: { id: user.id }, data: { diaRecebimento } });
  }

  /** LGPD art. 18 / Google Play User Data policy: apaga tudo que pertence ao usuário. */
  async deleteAccount(firebaseUid: string): Promise<void> {
    const user = await this.getByFirebaseUidOrThrow(firebaseUid);

    // Reusa a lógica de desconectar Gmail (revoga o token com o Google, best-effort, e apaga
    // GmailConnection + EmailSummary) em vez de duplicá-la aqui.
    await this.gmailConnectionsService.disconnect(firebaseUid);

    await this.prisma.$transaction([
      this.prisma.sensoryProfile.deleteMany({ where: { userId: user.id } }),
      this.prisma.trustedContact.deleteMany({ where: { userId: user.id } }),
      this.prisma.cardFavorito.deleteMany({ where: { userId: user.id } }),
      this.prisma.whatsappMensagem.deleteMany({ where: { userId: user.id } }),
      this.prisma.whatsappConversaEstado.deleteMany({ where: { userId: user.id } }),
      this.prisma.whatsappVinculo.deleteMany({ where: { userId: user.id } }),
      this.prisma.lancamentoFinanceiro.deleteMany({ where: { userId: user.id } }),
      this.prisma.contaFinanceira.deleteMany({ where: { userId: user.id } }),
      this.prisma.cartaoCredito.deleteMany({ where: { userId: user.id } }),
      this.prisma.user.delete({ where: { id: user.id } }),
    ]);

    try {
      await this.firebaseAdmin.auth().deleteUser(firebaseUid);
    } catch (error) {
      this.logger.warn(
        `Failed to delete Firebase Auth user during account deletion (DB already cleaned up): ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }
  }

  async getFeatureFlags(firebaseUid: string): Promise<FeatureFlags> {
    const user = await this.getByFirebaseUidOrThrow(firebaseUid);
    return resolveFeatureFlags(user.plano);
  }
}
