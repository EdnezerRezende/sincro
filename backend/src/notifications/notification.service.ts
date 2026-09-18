import { Inject, Injectable, Logger } from '@nestjs/common';
import { FIREBASE_ADMIN } from '../auth/firebase-admin.provider';
import type { FirebaseAdmin } from '../auth/firebase-admin.provider';
import { PrismaService } from '../prisma/prisma.service';
import { SensoryProfileService } from '../sensory-profile/sensory-profile.service';

@Injectable()
export class NotificationService {
  private readonly logger = new Logger(NotificationService.name);

  constructor(
    @Inject(FIREBASE_ADMIN) private readonly firebaseAdmin: FirebaseAdmin,
    private readonly prisma: PrismaService,
    private readonly sensoryProfileService: SensoryProfileService,
  ) {}

  async notifyNewEmailsNeedAttention(userId: string, count: number): Promise<void> {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user?.fcmToken) return;

    const sensoryProfile = await this.sensoryProfileService.get(user.firebaseUid);
    const tolerancia = (sensoryProfile?.dados as { toleranciaNotificacao?: string } | undefined)?.toleranciaNotificacao;

    // 'HORARIO_ESPECIFICO' não empurra notificação: a anamnese da Fase 1 nunca coletou a faixa
    // de horário real (só a categoria), então não há como saber se agora está dentro da janela
    // que o usuário pediu — até essa lacuna ser resolvida, tratamos como silencioso por segurança.
    if (tolerancia !== 'PADRAO') return;

    await this.firebaseAdmin.messaging().send({
      token: user.fcmToken,
      notification: {
        title: 'Sincro',
        body: count === 1 ? '1 e-mail precisa da sua atenção' : `${count} e-mails precisam da sua atenção`,
      },
      // Discriminator so the mobile client knows this tap should navigate to /inbox — and only
      // this kind of notification, not any future notification type added to the app.
      data: { tipo: 'email_triage' },
    });
  }

  async notifyContasVencendo(userId: string, count: number): Promise<void> {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user?.fcmToken) return;

    const sensoryProfile = await this.sensoryProfileService.get(user.firebaseUid);
    const tolerancia = (sensoryProfile?.dados as { toleranciaNotificacao?: string } | undefined)?.toleranciaNotificacao;
    if (tolerancia !== 'PADRAO') return;

    await this.firebaseAdmin.messaging().send({
      token: user.fcmToken,
      notification: {
        title: 'Sincro',
        body: count === 1 ? '1 conta está vencendo nos próximos dias' : `${count} contas estão vencendo nos próximos dias`,
      },
      data: { tipo: 'finance_alert' },
    });
  }

  /** Push SÓ DE DADOS: não aparece na bandeja de notificações do aparelho (sem campo
   *  `notification`), então não é uma interrupção sensorial e não passa pela tolerância de
   *  notificação da anamnese (`sensoryProfileService`) — diferente de `notifyNewEmailsNeedAttention`
   *  e `notifyContasVencendo`, que são visíveis e por isso respeitam essa preferência. O app, ao
   *  recebê-lo em segundo ou primeiro plano, apenas relê a caixa de entrada. */
  async notifyInboxAtualizada(userId: string): Promise<void> {
    // Corpo inteiro dentro do try — inclusive o findUnique e o early return sem fcmToken —
    // porque o método promete nunca lançar: uma rejeição do Prisma (ex.: timeout de pool)
    // não pode propagar e derrubar o ciclo do scheduler que dispara notificações visíveis.
    try {
      const user = await this.prisma.user.findUnique({ where: { id: userId } });
      if (!user?.fcmToken) return;

      await this.firebaseAdmin.messaging().send({
        token: user.fcmToken,
        data: { tipo: 'inbox_atualizada' },
        android: { priority: 'high' },
        apns: {
          headers: { 'apns-push-type': 'background', 'apns-priority': '5' },
          payload: { aps: { contentAvailable: true } },
        },
      });
    } catch (error) {
      this.logger.warn(`FCM inbox_atualizada falhou para ${userId}: ${this.descreverErro(error)}`);
    }
  }

  /** Normaliza um erro capturado em texto legível para log, cobrindo os formatos que o SDK
   *  do Firebase Admin e o Prisma costumam lançar/rejeitar (instância de `Error`, objeto com
   *  `code`/`message`, ou valores crus sem estrutura nenhuma). */
  private descreverErro(error: unknown): string {
    if (error instanceof Error) return error.message;

    if (error == null) return 'erro desconhecido';

    if (typeof error === 'object') {
      const { code, message } = error as { code?: unknown; message?: unknown };
      if (code !== undefined || message !== undefined) {
        const partes = [code, message].filter((parte) => parte !== undefined);
        return partes.join(': ');
      }
    }

    return String(error);
  }
}
