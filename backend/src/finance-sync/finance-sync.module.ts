import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { UsersModule } from '../users/users.module';
import { PluggyModule } from '../pluggy/pluggy.module';
import { FinanceSyncService } from './finance-sync.service';
import { FinanceWebhookController } from './finance-webhook.controller';
import { FinanceSyncController } from './finance-sync.controller';

@Module({
  imports: [AuthModule, UsersModule, PluggyModule],
  providers: [FinanceSyncService],
  controllers: [FinanceWebhookController, FinanceSyncController],
  exports: [FinanceSyncService],
})
export class FinanceSyncModule {}
