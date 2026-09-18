import { Injectable, Logger } from '@nestjs/common';
import { Cron, Interval } from '@nestjs/schedule';
import { OnEvent } from '@nestjs/event-emitter';
import { PrismaService } from '../prisma/prisma.service';
import { EmailSyncService } from './email-sync.service';
import { EmailSyncLockService } from './email-sync-lock.service';
import { NotificationService } from '../notifications/notification.service';

@Injectable()
export class EmailSyncScheduler {
  private readonly logger = new Logger(EmailSyncScheduler.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly emailSyncService: EmailSyncService,
    private readonly lockService: EmailSyncLockService,
    private readonly notificationService: NotificationService,
  ) {}

  /** a cada 2 minutos — sincronização rápida (spec aprovado, opção B + itens comuns) */
  @Cron('*/2 * * * *')
  async syncRapid(): Promise<void> {
    const connections = await this.prisma.gmailConnection.findMany({
      select: { userId: true },
    });
    for (const { userId } of connections) {
      const result = await this.lockService.executar(userId, async () => {
        try {
          const res = await this.emailSyncService.syncUser(userId);
          if (res.novosPrecisamAtencao > 0) {
            await this.notificationService.notifyNewEmailsNeedAttention(
              userId,
              res.novosPrecisamAtencao,
            );
          }
          return res;
        } catch (e) {
          this.logger.error(`Rapid sync failed for ${userId}`, e as Error);
          return { novos: 0, novosPrecisamAtencao: 0 };
        }
      });
      if (result === null) {
        this.logger.debug(`Skip ${userId}: already syncing`);
      }
    }
  }

  @OnEvent('gmail.conectado')
  async onGmailConnected(payload: { userId: string }): Promise<void> {
    this.logger.log(`Event gmail.conectado for ${payload.userId}`);
    const result = await this.lockService.executar(payload.userId, async () => {
      return this.emailSyncService.syncUser(payload.userId);
    });
    if (result) {
      this.logger.log(`Initial sync done for ${payload.userId}: ${result.novos} new`);
    }
  }
}
