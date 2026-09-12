import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { UsersModule } from '../users/users.module';
import { ContasController } from './contas.controller';
import { ContasService } from './contas.service';
import { EmailFinanceRegexParserService } from './parser/email-finance-regex-parser.service';
import { SaldoLivreCalculator } from './saldo-livre.calculator';

@Module({
  imports: [AuthModule, UsersModule],
  providers: [EmailFinanceRegexParserService, SaldoLivreCalculator, ContasService],
  controllers: [ContasController],
  exports: [EmailFinanceRegexParserService],
})
export class FinancasModule {}
