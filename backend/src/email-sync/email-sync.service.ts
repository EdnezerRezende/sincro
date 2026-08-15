import { Injectable, Logger, NotFoundException } from '@nestjs/common';
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
    let hasUnrecoverableFailure = false;
    for (const email of emails) {
      // Cheap pre-filter: avoids a wasted classifier call for messages we already know about.
      // This is NOT the source of truth for idempotency — the @@unique([userId, gmailMessageId])
      // constraint on the create() below is. Two overlapping sync runs can both pass this check
      // for the same message (check-then-act race); the try/catch around create() is what makes
      // the write itself safe, so a duplicate-key race can never throw and abort this loop (which
      // would otherwise prevent the gmailConnection.update below from ever running).
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

      try {
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
      } catch (error) {
        if (this.isDuplicateKeyError(error)) {
          this.logger.warn(
            `Message ${email.gmailMessageId} was already synced by a concurrent run, skipping (race-safe dedup)`,
          );
        } else {
          this.logger.error(`Failed to persist summary for message ${email.gmailMessageId}`, error as Error);
          // Not a duplicate-key race, so this message was never actually persisted. The cursor
          // must not advance past it this cycle, or it would never be retried (fetchIncremental
          // only looks forward from lastHistoryId) and would be silently lost.
          hasUnrecoverableFailure = true;
        }
        continue;
      }

      if (classification.categoria === 'PRECISA_ATENCAO') novosPrecisamAtencao++;
    }

    // Duplicate-key races are safe to skip past (the message was already persisted by a
    // concurrent run), so the cursor still advances in that case. But if a message failed to
    // persist for any other reason, skip the cursor update entirely so the next cron cycle
    // re-fetches and retries it — the messages that DID persist in this loop stay persisted,
    // only the cursor stays put.
    if (hasUnrecoverableFailure) {
      this.logger.warn(
        `Skipping lastHistoryId update for user ${userId}: at least one message failed to persist for a non-duplicate reason and must be retried next cycle`,
      );
    } else {
      await this.prisma.gmailConnection.update({
        where: { userId },
        data: { lastHistoryId: historyId, ultimaSincronizacao: new Date() },
      });
    }

    return { novosPrecisamAtencao };
  }

  /** Detects Prisma's unique-constraint violation (P2002) without importing the Prisma error class,
   *  so this stays resilient to whichever Prisma client version is actually installed. */
  private isDuplicateKeyError(error: unknown): boolean {
    return (error as { code?: string } | null)?.code === 'P2002';
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
      take: 100,
      // Project only what the mobile client actually reads (EmailSummary.fromJson), plus
      // gmailMessageId (kept for the e2e test's cross-tenant identity assertions and as a
      // natural key clients may want later) — never internal fields like userId, lidoNoApp,
      // criadoEm, or anything else beyond this list.
      select: {
        id: true,
        gmailMessageId: true,
        remetente: true,
        assunto: true,
        resumoCurto: true,
        categoria: true,
        recebidoEm: true,
      },
    });
  }

  async getOwned(firebaseUid: string, id: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const summary = await this.prisma.emailSummary.findFirst({ where: { id, userId: user.id } });
    if (!summary) {
      throw new NotFoundException('E-mail não encontrado.');
    }
    return summary;
  }
}
