import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { PrismaModule } from './prisma/prisma.module';
import { AuthModule } from './auth/auth.module';
import { UsersModule } from './users/users.module';
import { SensoryProfileModule } from './sensory-profile/sensory-profile.module';
import { TrustedContactsModule } from './trusted-contacts/trusted-contacts.module';
import { EmergencyModule } from './emergency/emergency.module';

@Module({
  imports: [
    PrismaModule,
    AuthModule,
    UsersModule,
    SensoryProfileModule,
    TrustedContactsModule,
    EmergencyModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
