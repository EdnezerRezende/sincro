import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { UsersModule } from '../users/users.module';
import { PluggyModule } from '../pluggy/pluggy.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { FinanceSyncService } from './finance-sync.service';
import { FinanceWebhookController } from './finance-webhook.controller';
import { FinanceSyncController } from './finance-sync.controller';
import { SaldoLivreCalculator } from './saldo-livre.calculator';
import { FinanceResumoController } from './finance-resumo.controller';
import { FinanceAlertScheduler } from './finance-alert.scheduler';

@Module({
  imports: [AuthModule, UsersModule, PluggyModule, NotificationsModule],
  providers: [FinanceSyncService, SaldoLivreCalculator, FinanceAlertScheduler],
  controllers: [FinanceWebhookController, FinanceSyncController, FinanceResumoController],
  exports: [FinanceSyncService],
})
export class FinanceSyncModule {}
