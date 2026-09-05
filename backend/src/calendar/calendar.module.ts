import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { UsersModule } from '../users/users.module';
import { GmailModule } from '../gmail/gmail.module';
import { CalendarApiClient } from './calendar-api-client.service';
import { CalendarController } from './calendar.controller';

@Module({
  imports: [AuthModule, UsersModule, GmailModule],
  providers: [CalendarApiClient],
  controllers: [CalendarController],
  exports: [CalendarApiClient],
})
export class CalendarModule {}
