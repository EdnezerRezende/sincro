import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationService } from '../notifications/notification.service';

const ALERT_WINDOW_DAYS = 3;

@Injectable()
export class FinanceAlertScheduler {
  private readonly logger = new Logger(FinanceAlertScheduler.name);
  private running = false;

  constructor(
    private readonly prisma: PrismaService,
    private readonly notificationService: NotificationService,
  ) {}

  // Fixamos o fuso: sem `timeZone` o cron roda no horário local do servidor, e num host
  // deployado em UTC "08:00" viraria 05:00 no Brasil — notificação em cima de gente dormindo,
  // exatamente o oposto do tom calmo que esse pilar propõe.
  @Cron('0 8 * * *', { timeZone: 'America/Sao_Paulo' })
  async checkContasVencendo(): Promise<void> {
    if (this.running) {
      this.logger.warn('checkContasVencendo is already running; skipping this cron firing to avoid overlap');
      return;
    }
    this.running = true;
    try {
      const hoje = new Date();
      // Piso em "hoje": sem ele, uma primeira sincronização trazendo anos de boletos vencidos
      // (todos com notificadoEm null) viraria um único push "N contas estão vencendo nos
      // próximos dias" — factualmente errado e punitivo.
      const piso = new Date(Date.UTC(hoje.getFullYear(), hoje.getMonth(), hoje.getDate()));
      const limite = new Date(Date.UTC(hoje.getFullYear(), hoje.getMonth(), hoje.getDate() + ALERT_WINDOW_DAYS));

      const boletos = await this.prisma.boletoDda.findMany({
        where: { pago: false, notificadoEm: null, vencimento: { gte: piso, lte: limite } },
      });
      const faturas = await this.prisma.financeAccount.findMany({
        where: { tipo: 'CARTAO_CREDITO', notificadoEm: null, vencimentoFatura: { gte: piso, lte: limite } },
        include: { conexao: true },
      });

      const porUsuario = new Map<string, { boletoIds: string[]; faturaIds: string[] }>();
      for (const boleto of boletos) {
        const entry = porUsuario.get(boleto.userId) ?? { boletoIds: [], faturaIds: [] };
        entry.boletoIds.push(boleto.id);
        porUsuario.set(boleto.userId, entry);
      }
      for (const fatura of faturas) {
        const userId = fatura.conexao.userId;
        const entry = porUsuario.get(userId) ?? { boletoIds: [], faturaIds: [] };
        entry.faturaIds.push(fatura.id);
        porUsuario.set(userId, entry);
      }

      for (const [userId, { boletoIds, faturaIds }] of porUsuario) {
        try {
          await this.notificationService.notifyContasVencendo(userId, boletoIds.length + faturaIds.length);
          if (boletoIds.length > 0) {
            await this.prisma.boletoDda.updateMany({ where: { id: { in: boletoIds } }, data: { notificadoEm: new Date() } });
          }
          if (faturaIds.length > 0) {
            await this.prisma.financeAccount.updateMany({ where: { id: { in: faturaIds } }, data: { notificadoEm: new Date() } });
          }
        } catch (error) {
          this.logger.error(`Failed to notify user ${userId} about upcoming contas`, error as Error);
        }
      }
    } finally {
      this.running = false;
    }
  }
}
