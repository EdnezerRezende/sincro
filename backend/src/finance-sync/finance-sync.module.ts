import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { UsersModule } from '../users/users.module';
import { PluggyModule } from '../pluggy/pluggy.module';
import { FinanceSyncService } from './finance-sync.service';
import { FinanceWebhookController } from './finance-webhook.controller';
import { FinanceSyncController } from './finance-sync.controller';
import { SaldoLivreCalculator } from './saldo-livre.calculator';
import { FinanceResumoController } from './finance-resumo.controller';

@Module({
  imports: [AuthModule, UsersModule, PluggyModule],
  providers: [FinanceSyncService, SaldoLivreCalculator],
  controllers: [FinanceWebhookController, FinanceSyncController, FinanceResumoController],
  exports: [FinanceSyncService],
})
export class FinanceSyncModule {}
