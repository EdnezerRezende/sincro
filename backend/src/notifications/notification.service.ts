import { Inject, Injectable } from '@nestjs/common';
import { FIREBASE_ADMIN } from '../auth/firebase-admin.provider';
import type { FirebaseAdmin } from '../auth/firebase-admin.provider';
import { PrismaService } from '../prisma/prisma.service';
import { SensoryProfileService } from '../sensory-profile/sensory-profile.service';

@Injectable()
export class NotificationService {
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
}
