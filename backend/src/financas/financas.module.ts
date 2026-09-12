import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { UsersModule } from '../users/users.module';
import { CartoesController } from './cartoes.controller';
import { CartoesService } from './cartoes.service';
import { ContasController } from './contas.controller';
import { ContasService } from './contas.service';
import { EmailFinanceRegexParserService } from './parser/email-finance-regex-parser.service';
import { SaldoLivreCalculator } from './saldo-livre.calculator';

@Module({
  imports: [AuthModule, UsersModule],
  providers: [EmailFinanceRegexParserService, SaldoLivreCalculator, ContasService, CartoesService],
  controllers: [ContasController, CartoesController],
  exports: [EmailFinanceRegexParserService],
})
export class FinancasModule {}
