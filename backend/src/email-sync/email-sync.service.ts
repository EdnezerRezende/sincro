import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { GmailApiClient } from '../gmail/gmail-api-client.service';
import { GmailConnectionsService } from '../gmail/gmail-connections.service';
import { SensoryProfileService } from '../sensory-profile/sensory-profile.service';
import { HeuristicEmailClassifier } from '../email-classification/heuristic-email-classifier.service';
import { LlmEmailClassifier } from '../email-classification/llm-email-classifier.service';
import { EmailClassifier } from '../email-classification/email-classifier.interface';
import { UsersService } from '../users/users.service';
import { FinanceEmailProcessor } from '../financas/parser/finance-email-processor.service';
import { FINANCE_PARSER_VERSION } from '../financas/parser/email-finance-regex-parser.service';
import { classificarErroGmail } from '../gmail/gmail-error.util';
import { MARCADOR_NOME } from '../gmail/gmail-api-client.service';

/** Tamanho do lote de reprocessamento (passo B) por usuário por ciclo — ver spec "Reprocessamento
 *  e escrita idempotente": com cron de 20 min, 500 summaries legados zeram em ~3h. */
const LOTE_REPROCESSAMENTO = 50;

interface Marcador {
  labelId: string | null;
  ids: Set<string>;
  /** true quando o passo 0 falhou neste ciclo (ver `resolverMarcador`) — o `Set` acima está vazio
   *  por segurança, não porque o usuário não rotulou nada. */
  indisponivel: boolean;
}

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
    private readonly financeProcessor: FinanceEmailProcessor,
  ) {}

  async syncUser(userId: string): Promise<{ novosPrecisamAtencao: number }> {
    const connection = await this.prisma.gmailConnection.findUnique({
      where: { userId },
    });
    if (!connection) return { novosPrecisamAtencao: 0 };

    const refreshToken =
      await this.connectionsService.getDecryptedRefreshToken(userId);
    if (!refreshToken) return { novosPrecisamAtencao: 0 };

    const marcador = await this.resolverMarcador(userId, refreshToken);

    const { emails, historyId } = await this.fetchNewEmails(
      refreshToken,
      connection.lastHistoryId,
    );

    const user = await this.prisma.user.findUniqueOrThrow({
      where: { id: userId },
    });
    const classifier: EmailClassifier =
      user.plano === 'pro' ? this.llmClassifier : this.heuristicClassifier;
    const sensoryProfile = await this.sensoryProfileService.get(
      user.firebaseUid,
    );
    const tomPreferido = (
      sensoryProfile?.dados as { tomPreferido?: string } | undefined
    )?.tomPreferido;

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
        where: {
          userId_gmailMessageId: {
            userId,
            gmailMessageId: email.gmailMessageId,
          },
        },
      });
      if (alreadySynced) continue;

      let classification;
      try {
        classification = await classifier.classify(
          {
            remetente: email.remetente,
            assunto: email.assunto,
            corpo: email.corpo,
          },
          { tomPreferido },
        );
      } catch (error) {
        this.logger.error(
          `Classification failed for message ${email.gmailMessageId}`,
          error as Error,
        );
        classification = {
          categoria: 'PODE_ESPERAR' as const,
          resumoCurto: email.assunto,
        };
      }

      const marcado = marcador.ids.has(email.gmailMessageId);
      const fin = await this.financeProcessor.processar(
        userId,
        refreshToken,
        email,
        { marcado },
      );
      const labelIds =
        marcado &&
        marcador.labelId &&
        !email.labelIds.includes(marcador.labelId)
          ? [...email.labelIds, marcador.labelId]
          : email.labelIds;

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
            labelIds,
            parserFinancasVersao:
              fin.transitorio || marcador.indisponivel
                ? null
                : FINANCE_PARSER_VERSION,
            parserFinancasTentativas: fin.transitorio ? 1 : 0,
          },
        });
      } catch (error) {
        if (this.isDuplicateKeyError(error)) {
          this.logger.warn(
            `Message ${email.gmailMessageId} was already synced by a concurrent run, skipping (race-safe dedup)`,
          );
        } else {
          this.logger.error(
            `Failed to persist summary for message ${email.gmailMessageId}`,
            error as Error,
          );
          // Not a duplicate-key race, so this message was never actually persisted. The cursor
          // must not advance past it this cycle, or it would never be retried (fetchIncremental
          // only looks forward from lastHistoryId) and would be silently lost.
          hasUnrecoverableFailure = true;
        }
        continue;
      }

      if (classification.categoria === 'PRECISA_ATENCAO')
        novosPrecisamAtencao++;
    }

    if (marcador.indisponivel) {
      // Rodar (B) agora, com o Set do marcador vazio por falha transitória, faria os e-mails já
      // rotulados pelo usuário perderem o marcador para sempre: como (A) já carimbou
      // parserFinancasVersao = null para os e-mails novos deste ciclo, o próximo ciclo (com o
      // marcador disponível de novo) revisita todo mundo pendente — inclusive esses.
      this.logger.warn(
        `Reprocessamento adiado para ${userId}: marcador indisponível neste ciclo`,
      );
    } else {
      await this.reprocessarPendentes(userId, refreshToken, marcador);
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

  /** Passo (0): lista as mensagens marcadas manualmente pelo usuário com o label `MARCADOR_NOME` —
   *  sinal de que a triagem automática perdeu um e-mail financeiro real. Re-enfileira ($executeRaw,
   *  já que o Prisma não expressa `NOT (label_ids @> ARRAY[...])` sem relação) só quem ainda não
   *  tinha o marcador persistido em `labelIds` — idempotente por evento: uma vez processado com
   *  `marcado: true`, o e-mail grava o labelId e não volta a ser re-enfileirado por este passo.
   *  Falha transitória aqui nunca derruba o ciclo, mas NÃO pode ser tratada como "sem marcador
   *  neste ciclo" e seguir em frente como se nada tivesse acontecido: com um Set vazio, um e-mail
   *  que o usuário rotulou e que (A) processa agora perderia o marcador para sempre — o Gmail já
   *  devolve o label em `email.labelIds`, então `NOT (label_ids @> ARRAY[...])` nunca mais o
   *  re-enfileira. Por isso o chamador usa `indisponivel` para carimbar `parserFinancasVersao =
   *  null` em (A) (revisita em (B) no próximo ciclo) e pular (B) inteiro neste ciclo. */
  private async resolverMarcador(
    userId: string,
    refreshToken: string,
  ): Promise<Marcador> {
    try {
      const marcador =
        await this.gmailApiClient.listarIdsComMarcador(refreshToken);
      if (marcador.labelId && marcador.ids.size > 0) {
        await this.prisma.$executeRaw`
          UPDATE resumos_email SET parser_financas_versao = NULL
          WHERE user_id = ${userId} AND gmail_message_id = ANY(${Array.from(marcador.ids)}::text[])
            AND NOT (label_ids @> ARRAY[${marcador.labelId}]::text[])`;
      }
      return { ...marcador, indisponivel: false };
    } catch (error) {
      this.logger.warn(
        `Marcador ${MARCADOR_NOME} indisponível neste ciclo (${classificarErroGmail(error)}); seguindo sem ele`,
        error as Error,
      );
      return { labelId: null, ids: new Set(), indisponivel: true };
    }
  }

  /** Passo (B): e-mails já sincronizados que o parser financeiro atual ainda não avaliou
   *  (`parserFinancasVersao` nulo ou desatualizado). Fila ordenada por tentativas ascendente (uma
   *  mensagem venenosa afunda para o fim sem bloquear as demais) e recebidoEm descendente dentro do
   *  mesmo nível de tentativas. Erro transitório NUNCA carimba a versão — o e-mail permanece
   *  elegível para sempre; transitório-conta interrompe o lote inteiro (afeta todos os e-mails
   *  deste usuário), transitório-mensagem só pula este e segue para o próximo. */
  private async reprocessarPendentes(
    userId: string,
    refreshToken: string,
    marcador: Marcador,
  ): Promise<void> {
    const pendentes = await this.prisma.emailSummary.findMany({
      where: {
        userId,
        OR: [
          { parserFinancasVersao: null },
          { parserFinancasVersao: { lt: FINANCE_PARSER_VERSION } },
        ],
      },
      orderBy: [{ parserFinancasTentativas: 'asc' }, { recebidoEm: 'desc' }],
      take: LOTE_REPROCESSAMENTO,
    });

    for (const s of pendentes) {
      const marcado = marcador.ids.has(s.gmailMessageId);
      const fin = await this.financeProcessor.processar(
        userId,
        refreshToken,
        {
          gmailMessageId: s.gmailMessageId,
          remetente: s.remetente,
          assunto: s.assunto,
          recebidoEm: s.recebidoEm,
        },
        { marcado },
      );

      if (fin.transitorio) {
        await this.prisma.emailSummary.update({
          where: { id: s.id },
          data: { parserFinancasTentativas: { increment: 1 } },
        });
        if (fin.classe === 'transitorio-conta') {
          this.logger.warn(
            `Reprocessamento interrompido para ${userId}: Gmail indisponível`,
          );
          break;
        }
        continue;
      }

      const labelIds =
        marcado && marcador.labelId && !s.labelIds.includes(marcador.labelId)
          ? [...s.labelIds, marcador.labelId]
          : s.labelIds;
      await this.prisma.emailSummary.update({
        where: { id: s.id },
        data: {
          parserFinancasVersao: FINANCE_PARSER_VERSION,
          parserFinancasTentativas: 0,
          labelIds,
        },
      });
    }
  }

  private async fetchNewEmails(
    refreshToken: string,
    lastHistoryId: string | null,
  ) {
    if (!lastHistoryId) {
      return this.gmailApiClient.fetchInitialUnread(refreshToken);
    }

    const incremental = await this.gmailApiClient.fetchIncremental(
      refreshToken,
      lastHistoryId,
    );
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
    const summary = await this.prisma.emailSummary.findFirst({
      where: { id, userId: user.id },
    });
    if (!summary) {
      throw new NotFoundException('E-mail não encontrado.');
    }
    return summary;
  }

  /** Removes the local row for arquivar/excluir (see `EmailSummaryController`). Both actions must
   *  take the row out of `resumos_email` in the SAME request that acts on Gmail — the sync cron
   *  only ever handles `messageAdded` history events (see `GmailApiClient.fetchIncremental`), so
   *  it would never notice (and never remove) a message the user archived or trashed. Takes the
   *  already-fetched `id` (not the Gmail message id) — the caller has already resolved ownership
   *  via `getOwned` before calling this. */
  async remover(id: string): Promise<void> {
    await this.prisma.emailSummary.delete({ where: { id } });
  }
}
