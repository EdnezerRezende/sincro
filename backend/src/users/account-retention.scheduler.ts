import { Inject, Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import type { GetUsersResult } from 'firebase-admin/auth';
import { PrismaService } from '../prisma/prisma.service';
import { FIREBASE_ADMIN } from '../auth/firebase-admin.provider';
import type { FirebaseAdmin } from '../auth/firebase-admin.provider';
import { UsersService } from './users.service';

const RETENTION_DAYS = 90;
// getUsers() do firebase-admin só aceita até 100 identificadores por chamada.
const FIREBASE_BATCH_SIZE = 100;

/** LGPD art. 16 / declaração do Play Console ("dados excluídos automaticamente em 90 dias"):
 *  apaga contas sem atividade de login há 90+ dias. "Atividade" usa o `lastSignInTime` do
 *  próprio Firebase Auth (fonte de verdade de login) em vez de um campo próprio replicado no
 *  Postgres — evita migração e evita o campo divergir do que o Firebase realmente registra.
 *  Conta sem registro correspondente no Firebase Auth (apagada direto no console, por exemplo)
 *  é tratada como órfã e removida no mesmo ciclo: não há como ela voltar a ficar "ativa". */
@Injectable()
export class AccountRetentionScheduler {
  private readonly logger = new Logger(AccountRetentionScheduler.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly usersService: UsersService,
    @Inject(FIREBASE_ADMIN) private readonly firebaseAdmin: FirebaseAdmin,
  ) {}

  @Cron(CronExpression.EVERY_DAY_AT_3AM)
  async purgeInactiveAccounts(): Promise<void> {
    const users = await this.prisma.user.findMany({ select: { firebaseUid: true, createdAt: true } });
    if (users.length === 0) return;

    const cutoff = new Date(Date.now() - RETENTION_DAYS * 24 * 60 * 60 * 1000);
    let apagadas = 0;

    for (let i = 0; i < users.length; i += FIREBASE_BATCH_SIZE) {
      const lote = users.slice(i, i + FIREBASE_BATCH_SIZE);
      let resultado: GetUsersResult;
      try {
        resultado = await this.firebaseAdmin
          .auth()
          .getUsers(lote.map(({ firebaseUid }) => ({ uid: firebaseUid })));
      } catch (error) {
        // Falha ao consultar o Firebase não deve derrubar ninguém por engano — pula o lote e
        // tenta de novo no próximo ciclo, em vez de apagar contas cuja atividade não confirmou.
        this.logger.error(
          `Failed to fetch Firebase Auth users for retention check (skipping this batch): ${
            error instanceof Error ? error.message : String(error)
          }`,
        );
        continue;
      }

      const porUid = new Map(resultado.users.map((u) => [u.uid, u]));

      for (const { firebaseUid, createdAt } of lote) {
        const firebaseUser = porUid.get(firebaseUid);
        // Sem registro no Firebase Auth = conta órfã (ex.: apagada direto no console). Nunca
        // mais vai ter atividade, então é elegível imediatamente.
        const ultimaAtividade = firebaseUser?.metadata.lastSignInTime
          ? new Date(firebaseUser.metadata.lastSignInTime)
          : createdAt;

        if (ultimaAtividade > cutoff) continue;

        try {
          await this.usersService.deleteAccount(firebaseUid);
          apagadas++;
        } catch (error) {
          this.logger.error(
            `Failed to delete inactive account ${firebaseUid} during retention purge: ${
              error instanceof Error ? error.message : String(error)
            }`,
          );
        }
      }
    }

    if (apagadas > 0) {
      this.logger.log(`Retention purge: ${apagadas} conta(s) inativa(s) há ${RETENTION_DAYS}+ dias apagada(s).`);
    }
  }
}
