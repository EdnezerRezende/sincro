import { Module } from '@nestjs/common';
import { EmailFinanceRegexParserService } from './parser/email-finance-regex-parser.service';
import { SaldoLivreCalculator } from './saldo-livre.calculator';

@Module({
  providers: [EmailFinanceRegexParserService, SaldoLivreCalculator],
  exports: [EmailFinanceRegexParserService],
})
export class FinancasModule {}
