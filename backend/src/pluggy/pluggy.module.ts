import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { UsersModule } from '../users/users.module';
import { PluggyApiClient } from './pluggy-api-client.service';
import { FinanceConnectionsService } from './finance-connections.service';
import { FinanceController } from './finance.controller';

@Module({
  imports: [AuthModule, UsersModule],
  providers: [PluggyApiClient, FinanceConnectionsService],
  controllers: [FinanceController],
  exports: [PluggyApiClient, FinanceConnectionsService],
})
export class PluggyModule {}
