import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { UsersModule } from '../users/users.module';
import { TrustedContactsService } from './trusted-contacts.service';
import { TrustedContactsController } from './trusted-contacts.controller';

@Module({
  imports: [AuthModule, UsersModule],
  providers: [TrustedContactsService],
  controllers: [TrustedContactsController],
  exports: [TrustedContactsService],
})
export class TrustedContactsModule {}
