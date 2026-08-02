import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { GmailModule } from '../gmail/gmail.module';
import { SensoryProfileModule } from '../sensory-profile/sensory-profile.module';
import { EmailClassificationModule } from '../email-classification/email-classification.module';
import { UsersModule } from '../users/users.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { EmailSyncService } from './email-sync.service';
import { EmailSyncScheduler } from './email-sync.scheduler';
import { EmailSummaryController } from './email-summary.controller';

@Module({
  imports: [
    AuthModule,
    GmailModule,
    SensoryProfileModule,
    EmailClassificationModule,
    UsersModule,
    NotificationsModule,
  ],
  providers: [EmailSyncService, EmailSyncScheduler],
  controllers: [EmailSummaryController],
  exports: [EmailSyncService],
})
export class EmailSyncModule {}
