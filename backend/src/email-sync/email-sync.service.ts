import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { GmailApiClient } from '../gmail/gmail-api-client.service';
import { GmailConnectionsService } from '../gmail/gmail-connections.service';
import { SensoryProfileService } from '../sensory-profile/sensory-profile.service';
import { HeuristicEmailClassifier } from '../email-classification/heuristic-email-classifier.service';
import { LlmEmailClassifier } from '../email-classification/llm-email-classifier.service';
import { EmailClassifier } from '../email-classification/email-classifier.interface';
import { UsersService } from '../users/users.service';

@Injectable()
export class EmailSyncService {
  private readonly logger = new Logger(EmailSyncService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly gmailApiClient: GmailApiClient,
    private readonly connectionsService: GmailConnectionsService,
    private readonly sensoryProfileService: SensoryProfileService,
    private readonly heuristicClassifier: HeuristicEmailClassifier,
    private readonly llmClassifier: LlmEmailClassifier,
    private readonly usersService: UsersService,
  ) {}

  async syncUser(userId: string): Promise<{ novosPrecisamAtencao: number }> {
    const connection = await this.prisma.gmailConnection.findUnique({ where: { userId } });
    if (!connection) return { novosPrecisamAtencao: 0 };

    const refreshToken = await this.connectionsService.getDecryptedRefreshToken(userId);
    if (!refreshToken) return { novosPrecisamAtencao: 0 };

    const { emails, historyId } = await this.fetchNewEmails(refreshToken, connection.lastHistoryId);

    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });
    const classifier: EmailClassifier = user.plano === 'pro' ? this.llmClassifier : this.heuristicClassifier;
    const sensoryProfile = await this.sensoryProfileService.get(user.firebaseUid);
    const tomPreferido = (sensoryProfile?.dados as { tomPreferido?: string } | undefined)?.tomPreferido;

    let novosPrecisamAtencao = 0;
    for (const email of emails) {
      const alreadySynced = await this.prisma.emailSummary.findUnique({
        where: { userId_gmailMessageId: { userId, gmailMessageId: email.gmailMessageId } },
      });
      if (alreadySynced) continue;

      let classification;
      try {
        classification = await classifier.classify(
          { remetente: email.remetente, assunto: email.assunto, corpo: email.corpo },
          { tomPreferido },
        );
      } catch (error) {
        this.logger.error(`Classification failed for message ${email.gmailMessageId}`, error as Error);
        classification = { categoria: 'PODE_ESPERAR' as const, resumoCurto: email.assunto };
      }

      await this.prisma.emailSummary.create({
        data: {
          userId,
          gmailMessageId: email.gmailMessageId,
          remetente: email.remetente,
          assunto: email.assunto,
          resumoCurto: classification.resumoCurto,
          categoria: classification.categoria,
          recebidoEm: email.recebidoEm,
        },
      });

      if (classification.categoria === 'PRECISA_ATENCAO') novosPrecisamAtencao++;
    }

    await this.prisma.gmailConnection.update({
      where: { userId },
      data: { lastHistoryId: historyId, ultimaSincronizacao: new Date() },
    });

    return { novosPrecisamAtencao };
  }

  private async fetchNewEmails(refreshToken: string, lastHistoryId: string | null) {
    if (!lastHistoryId) {
      return this.gmailApiClient.fetchInitialUnread(refreshToken);
    }

    const incremental = await this.gmailApiClient.fetchIncremental(refreshToken, lastHistoryId);
    if (!incremental.historyExpired) {
      return { emails: incremental.emails, historyId: incremental.historyId };
    }

    this.logger.warn(`historyId expired, falling back to a full sync`);
    return this.gmailApiClient.fetchInitialUnread(refreshToken);
  }

  async list(firebaseUid: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    return this.prisma.emailSummary.findMany({
      where: { userId: user.id },
      orderBy: { recebidoEm: 'desc' },
    });
  }
}
