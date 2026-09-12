import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { CalendarModule } from '../calendar/calendar.module';
import { GmailModule } from '../gmail/gmail.module';
import { UsersModule } from '../users/users.module';
import { CartoesController } from './cartoes.controller';
import { CartoesService } from './cartoes.service';
import { FinanceCalendarSyncService } from './calendar-sync.service';
import { ContasController } from './contas.controller';
import { ContasService } from './contas.service';
import { LancamentosController } from './lancamentos.controller';
import { LancamentosService } from './lancamentos.service';
import { EmailFinanceRegexParserService } from './parser/email-finance-regex-parser.service';
import { ResumoController } from './resumo.controller';
import { SaldoLivreCalculator } from './saldo-livre.calculator';

@Module({
  imports: [AuthModule, UsersModule, CalendarModule, GmailModule],
  providers: [
    EmailFinanceRegexParserService,
    SaldoLivreCalculator,
    ContasService,
    CartoesService,
    FinanceCalendarSyncService,
    LancamentosService,
  ],
  controllers: [ContasController, CartoesController, LancamentosController, ResumoController],
  exports: [EmailFinanceRegexParserService],
})
export class FinancasModule {}
