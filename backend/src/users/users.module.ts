import { Module, forwardRef } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { GmailModule } from '../gmail/gmail.module';
import { UsersService } from './users.service';
import { UsersController } from './users.controller';
import { AccountRetentionScheduler } from './account-retention.scheduler';

@Module({
  imports: [AuthModule, forwardRef(() => GmailModule)],
  providers: [UsersService, AccountRetentionScheduler],
  controllers: [UsersController],
  exports: [UsersService],
})
export class UsersModule {}
