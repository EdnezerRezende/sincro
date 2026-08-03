import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { PrismaService } from '../prisma/prisma.service';
import { EmailSyncService } from './email-sync.service';
import { NotificationService } from '../notifications/notification.service';

@Injectable()
export class EmailSyncScheduler {
  private readonly logger = new Logger(EmailSyncScheduler.name);

  // In-instance re-entrancy guard: a sync cycle can outrun the 20-minute cron interval once
  // there are enough connected users (fetchMessages fetches sequentially), which would otherwise
  // let two cron firings process the same user concurrently and race on the emailSummary dedup.
  private running = false;

  constructor(
    private readonly prisma: PrismaService,
    private readonly emailSyncService: EmailSyncService,
    private readonly notificationService: NotificationService,
  ) {}

  @Cron('*/20 * * * *')
  async syncAllConnectedUsers(): Promise<void> {
    if (this.running) {
      this.logger.warn('syncAllConnectedUsers is already running; skipping this cron firing to avoid overlap');
      return;
    }
    this.running = true;
    try {
      const connections = await this.prisma.gmailConnection.findMany({ select: { userId: true } });
      for (const { userId } of connections) {
        try {
          const { novosPrecisamAtencao } = await this.emailSyncService.syncUser(userId);
          if (novosPrecisamAtencao > 0) {
            await this.notificationService.notifyNewEmailsNeedAttention(userId, novosPrecisamAtencao);
          }
        } catch (error) {
          this.logger.error(`Failed to sync Gmail for user ${userId}`, error as Error);
        }
      }
    } finally {
      this.running = false;
    }
  }
}
