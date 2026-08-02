import { Module } from '@nestjs/common';
import { PrismaModule } from './prisma/prisma.module';
import { AuthModule } from './auth/auth.module';
import { UsersModule } from './users/users.module';
import { SensoryProfileModule } from './sensory-profile/sensory-profile.module';
import { TrustedContactsModule } from './trusted-contacts/trusted-contacts.module';
import { EmergencyModule } from './emergency/emergency.module';
import { GmailModule } from './gmail/gmail.module';
import { EmailSyncModule } from './email-sync/email-sync.module';

@Module({
  imports: [
    PrismaModule,
    AuthModule,
    UsersModule,
    SensoryProfileModule,
    TrustedContactsModule,
    EmergencyModule,
    GmailModule,
    EmailSyncModule,
  ],
})
export class AppModule {}
