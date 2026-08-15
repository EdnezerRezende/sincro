import { Module } from '@nestjs/common';
import { GmailModule } from '../gmail/gmail.module';
import { CalendarApiClient } from './calendar-api-client.service';

@Module({
  imports: [GmailModule],
  providers: [CalendarApiClient],
  exports: [CalendarApiClient],
})
export class CalendarModule {}
