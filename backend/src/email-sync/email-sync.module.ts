import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { GmailModule } from '../gmail/gmail.module';
import { SensoryProfileModule } from '../sensory-profile/sensory-profile.module';
import { EmailClassificationModule } from '../email-classification/email-classification.module';
import { UsersModule } from '../users/users.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { FinancasModule } from '../financas/financas.module';
import { EmailSyncService } from './email-sync.service';
import { EmailSyncScheduler } from './email-sync.scheduler';
import { EmailSyncLockService } from './email-sync-lock.service';
import { EmailSummaryController } from './email-summary.controller';

@Module({
  imports: [
    AuthModule,
    GmailModule,
    SensoryProfileModule,
    EmailClassificationModule,
    UsersModule,
    NotificationsModule,
    FinancasModule,
  ],
  providers: [EmailSyncService, EmailSyncScheduler, EmailSyncLockService],
  controllers: [EmailSummaryController],
  exports: [EmailSyncService, EmailSyncLockService],
})
export class EmailSyncModule {}
