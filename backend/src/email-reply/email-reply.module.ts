import { Module } from '@nestjs/common';
import Anthropic from '@anthropic-ai/sdk';
import { AuthModule } from '../auth/auth.module';
import { UsersModule } from '../users/users.module';
import { GmailModule } from '../gmail/gmail.module';
import { CalendarModule } from '../calendar/calendar.module';
import { EmailSyncModule } from '../email-sync/email-sync.module';
import { EmailDraftService } from './email-draft.service';
import { EmailCommitmentExtractionService } from './email-commitment-extraction.service';
import { EmailReplyController } from './email-reply.controller';

const EMAIL_REPLY_ANTHROPIC_CLIENT = 'EMAIL_REPLY_ANTHROPIC_CLIENT';

@Module({
  imports: [AuthModule, UsersModule, GmailModule, CalendarModule, EmailSyncModule],
  providers: [
    {
      provide: EMAIL_REPLY_ANTHROPIC_CLIENT,
      useFactory: () => new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY }),
    },
    {
      provide: EmailDraftService,
      useFactory: (client: Anthropic) => new EmailDraftService(client),
      inject: [EMAIL_REPLY_ANTHROPIC_CLIENT],
    },
    {
      provide: EmailCommitmentExtractionService,
      useFactory: (client: Anthropic) => new EmailCommitmentExtractionService(client),
      inject: [EMAIL_REPLY_ANTHROPIC_CLIENT],
    },
  ],
  controllers: [EmailReplyController],
})
export class EmailReplyModule {}
