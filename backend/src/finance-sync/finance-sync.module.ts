import { Module } from '@nestjs/common';
import { UsersModule } from '../users/users.module';
import { PluggyModule } from '../pluggy/pluggy.module';
import { FinanceSyncService } from './finance-sync.service';

@Module({
  imports: [UsersModule, PluggyModule],
  providers: [FinanceSyncService],
  exports: [FinanceSyncService],
})
export class FinanceSyncModule {}
