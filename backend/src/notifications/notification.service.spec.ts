import { NotificationService } from './notification.service';

function buildDeps() {
  const send = jest.fn().mockResolvedValue('message-id');
  const firebaseAdmin = { messaging: () => ({ send }) };
  const prisma = { user: { findUnique: jest.fn() } };
  const sensoryProfileService = { get: jest.fn() };
  return { firebaseAdmin, prisma, sensoryProfileService, send };
}

describe('NotificationService', () => {
  it('sends an aggregated notification when toleranciaNotificacao is PADRAO', async () => {
    const { firebaseAdmin, prisma, sensoryProfileService, send } = buildDeps();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', fcmToken: 'token-abc' });
    sensoryProfileService.get.mockResolvedValue({ dados: { toleranciaNotificacao: 'PADRAO' } });
    const service = new NotificationService(firebaseAdmin as any, prisma as any, sensoryProfileService as any);

    await service.notifyNewEmailsNeedAttention('u1', 3);

    expect(send).toHaveBeenCalledWith({
      token: 'token-abc',
      notification: { title: 'Sincro', body: '3 e-mails precisam da sua atenção' },
    });
  });

  it('uses singular phrasing for exactly one email', async () => {
    const { firebaseAdmin, prisma, sensoryProfileService, send } = buildDeps();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', fcmToken: 'token-abc' });
    sensoryProfileService.get.mockResolvedValue({ dados: { toleranciaNotificacao: 'PADRAO' } });
    const service = new NotificationService(firebaseAdmin as any, prisma as any, sensoryProfileService as any);

    await service.notifyNewEmailsNeedAttention('u1', 1);

    expect(send).toHaveBeenCalledWith(
      expect.objectContaining({ notification: expect.objectContaining({ body: '1 e-mail precisa da sua atenção' }) }),
    );
  });

  it('does not send when toleranciaNotificacao is SILENCIOSAS', async () => {
    const { firebaseAdmin, prisma, sensoryProfileService, send } = buildDeps();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', fcmToken: 'token-abc' });
    sensoryProfileService.get.mockResolvedValue({ dados: { toleranciaNotificacao: 'SILENCIOSAS' } });
    const service = new NotificationService(firebaseAdmin as any, prisma as any, sensoryProfileService as any);

    await service.notifyNewEmailsNeedAttention('u1', 3);

    expect(send).not.toHaveBeenCalled();
  });

  it('does not send when toleranciaNotificacao is HORARIO_ESPECIFICO (no time window is stored yet)', async () => {
    const { firebaseAdmin, prisma, sensoryProfileService, send } = buildDeps();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', fcmToken: 'token-abc' });
    sensoryProfileService.get.mockResolvedValue({ dados: { toleranciaNotificacao: 'HORARIO_ESPECIFICO' } });
    const service = new NotificationService(firebaseAdmin as any, prisma as any, sensoryProfileService as any);

    await service.notifyNewEmailsNeedAttention('u1', 3);

    expect(send).not.toHaveBeenCalled();
  });

  it('does not send when the user has no fcmToken registered', async () => {
    const { firebaseAdmin, prisma, sensoryProfileService, send } = buildDeps();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', fcmToken: null });
    const service = new NotificationService(firebaseAdmin as any, prisma as any, sensoryProfileService as any);

    await service.notifyNewEmailsNeedAttention('u1', 3);

    expect(send).not.toHaveBeenCalled();
    expect(sensoryProfileService.get).not.toHaveBeenCalled();
  });
});
