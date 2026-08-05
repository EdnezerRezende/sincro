import { Module } from '@nestjs/common';
import { ScheduleModule } from '@nestjs/schedule';
import { PrismaModule } from './prisma/prisma.module';
import { AuthModule } from './auth/auth.module';
import { UsersModule } from './users/users.module';
import { SensoryProfileModule } from './sensory-profile/sensory-profile.module';
import { TrustedContactsModule } from './trusted-contacts/trusted-contacts.module';
import { EmergencyModule } from './emergency/emergency.module';
import { GmailModule } from './gmail/gmail.module';
import { EmailSyncModule } from './email-sync/email-sync.module';
import { PluggyModule } from './pluggy/pluggy.module';
import { FinanceSyncModule } from './finance-sync/finance-sync.module';
import { ProfessionalsModule } from './professionals/professionals.module';

@Module({
  imports: [
    ScheduleModule.forRoot(),
    PrismaModule,
    AuthModule,
    UsersModule,
    SensoryProfileModule,
    TrustedContactsModule,
    EmergencyModule,
    GmailModule,
    EmailSyncModule,
    PluggyModule,
    FinanceSyncModule,
    ProfessionalsModule,
  ],
})
export class AppModule {}
