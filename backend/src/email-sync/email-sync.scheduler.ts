import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { PrismaService } from '../prisma/prisma.service';
import { EmailSyncService } from './email-sync.service';
import { NotificationService } from '../notifications/notification.service';

@Injectable()
export class EmailSyncScheduler {
  private readonly logger = new Logger(EmailSyncScheduler.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly emailSyncService: EmailSyncService,
    private readonly notificationService: NotificationService,
  ) {}

  @Cron('*/20 * * * *')
  async syncAllConnectedUsers(): Promise<void> {
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
  }
}
