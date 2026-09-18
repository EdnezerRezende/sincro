import { Logger } from '@nestjs/common';
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
      data: { tipo: 'email_triage' },
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

describe('notifyContasVencendo', () => {
  it('sends an aggregated notification when toleranciaNotificacao is PADRAO', async () => {
    const { firebaseAdmin, prisma, sensoryProfileService, send } = buildDeps();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', fcmToken: 'token-abc' });
    sensoryProfileService.get.mockResolvedValue({ dados: { toleranciaNotificacao: 'PADRAO' } });
    const service = new NotificationService(firebaseAdmin as any, prisma as any, sensoryProfileService as any);

    await service.notifyContasVencendo('u1', 2);

    expect(send).toHaveBeenCalledWith({
      token: 'token-abc',
      notification: { title: 'Sincro', body: '2 contas estão vencendo nos próximos dias' },
      data: { tipo: 'finance_alert' },
    });
  });

  it('uses singular phrasing for exactly one conta', async () => {
    const { firebaseAdmin, prisma, sensoryProfileService, send } = buildDeps();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', fcmToken: 'token-abc' });
    sensoryProfileService.get.mockResolvedValue({ dados: { toleranciaNotificacao: 'PADRAO' } });
    const service = new NotificationService(firebaseAdmin as any, prisma as any, sensoryProfileService as any);

    await service.notifyContasVencendo('u1', 1);

    expect(send).toHaveBeenCalledWith(
      expect.objectContaining({ notification: expect.objectContaining({ body: '1 conta está vencendo nos próximos dias' }) }),
    );
  });

  it('does not send when toleranciaNotificacao is SILENCIOSAS', async () => {
    const { firebaseAdmin, prisma, sensoryProfileService, send } = buildDeps();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', fcmToken: 'token-abc' });
    sensoryProfileService.get.mockResolvedValue({ dados: { toleranciaNotificacao: 'SILENCIOSAS' } });
    const service = new NotificationService(firebaseAdmin as any, prisma as any, sensoryProfileService as any);

    await service.notifyContasVencendo('u1', 2);

    expect(send).not.toHaveBeenCalled();
  });

  it('does not send when the user has no fcmToken registered', async () => {
    const { firebaseAdmin, prisma, sensoryProfileService, send } = buildDeps();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', fcmToken: null });
    const service = new NotificationService(firebaseAdmin as any, prisma as any, sensoryProfileService as any);

    await service.notifyContasVencendo('u1', 2);

    expect(send).not.toHaveBeenCalled();
    expect(sensoryProfileService.get).not.toHaveBeenCalled();
  });
});

describe('notifyInboxAtualizada', () => {
  let warnSpy: jest.SpyInstance;

  beforeEach(() => {
    warnSpy = jest.spyOn(Logger.prototype, 'warn').mockImplementation(() => undefined);
  });

  afterEach(() => {
    warnSpy.mockRestore();
  });

  it('envia mensagem só de dados, sem notification e sem checar tolerância', async () => {
    const { firebaseAdmin, prisma, sensoryProfileService, send } = buildDeps();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', fcmToken: 'tok' });
    const service = new NotificationService(firebaseAdmin as any, prisma as any, sensoryProfileService as any);

    await service.notifyInboxAtualizada('u1');

    expect(sensoryProfileService.get).not.toHaveBeenCalled();
    expect(send).toHaveBeenCalledWith({
      token: 'tok',
      data: { tipo: 'inbox_atualizada' },
      android: { priority: 'high' },
      apns: { headers: { 'apns-push-type': 'background', 'apns-priority': '5' }, payload: { aps: { contentAvailable: true } } },
    });
    expect(send.mock.calls[0][0]).not.toHaveProperty('notification');
  });

  it('sem fcmToken não envia', async () => {
    const { firebaseAdmin, prisma, sensoryProfileService, send } = buildDeps();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', fcmToken: null });
    const service = new NotificationService(firebaseAdmin as any, prisma as any, sensoryProfileService as any);

    await service.notifyInboxAtualizada('u1');

    expect(send).not.toHaveBeenCalled();
    expect(sensoryProfileService.get).not.toHaveBeenCalled();
    expect(warnSpy).not.toHaveBeenCalled();
  });

  it('token inválido não propaga e loga o aviso com o userId', async () => {
    const { firebaseAdmin, prisma, sensoryProfileService, send } = buildDeps();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', fcmToken: 'tok' });
    send.mockRejectedValue(new Error('registration-token-not-registered'));
    const service = new NotificationService(firebaseAdmin as any, prisma as any, sensoryProfileService as any);

    await expect(service.notifyInboxAtualizada('u1')).resolves.toBeUndefined();

    expect(warnSpy).toHaveBeenCalledWith(expect.stringContaining('u1'));
    expect(warnSpy).toHaveBeenCalledWith(expect.stringContaining('registration-token-not-registered'));
  });

  it('erro do Prisma ao buscar o usuário não propaga e não chama send', async () => {
    const { firebaseAdmin, prisma, sensoryProfileService, send } = buildDeps();
    prisma.user.findUnique.mockRejectedValue(new Error('P2024: Timed out fetching a new connection from the pool'));
    const service = new NotificationService(firebaseAdmin as any, prisma as any, sensoryProfileService as any);

    await expect(service.notifyInboxAtualizada('u1')).resolves.toBeUndefined();

    expect(send).not.toHaveBeenCalled();
    expect(warnSpy).toHaveBeenCalledWith(expect.stringContaining('u1'));
  });

  it('erro do Prisma ao buscar o usuário também não consulta o perfil sensorial', async () => {
    const { firebaseAdmin, prisma, sensoryProfileService } = buildDeps();
    prisma.user.findUnique.mockRejectedValue(new Error('P2024: Timed out fetching a new connection from the pool'));
    const service = new NotificationService(firebaseAdmin as any, prisma as any, sensoryProfileService as any);

    await expect(service.notifyInboxAtualizada('u1')).resolves.toBeUndefined();

    expect(sensoryProfileService.get).not.toHaveBeenCalled();
  });

  it('rejeição não-Error (string) é logada em vez de gerar "undefined"', async () => {
    const { firebaseAdmin, prisma, sensoryProfileService, send } = buildDeps();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', fcmToken: 'tok' });
    send.mockRejectedValue('falha-crua-sem-classe-error');
    const service = new NotificationService(firebaseAdmin as any, prisma as any, sensoryProfileService as any);

    await expect(service.notifyInboxAtualizada('u1')).resolves.toBeUndefined();

    expect(warnSpy).toHaveBeenCalledWith(expect.stringContaining('falha-crua-sem-classe-error'));
    expect(warnSpy).not.toHaveBeenCalledWith(expect.stringContaining('undefined'));
  });

  it('firebaseAdmin.messaging() lança de forma síncrona e ainda assim não propaga', async () => {
    const prisma = { user: { findUnique: jest.fn() } };
    const sensoryProfileService = { get: jest.fn() };
    const firebaseAdmin = {
      messaging: () => {
        throw new Error('The default Firebase app does not exist');
      },
    };
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', fcmToken: 'tok' });
    const service = new NotificationService(firebaseAdmin as any, prisma as any, sensoryProfileService as any);

    await expect(service.notifyInboxAtualizada('u1')).resolves.toBeUndefined();

    expect(warnSpy).toHaveBeenCalledWith(expect.stringContaining('u1'));
    expect(warnSpy).toHaveBeenCalledWith(expect.stringContaining('The default Firebase app does not exist'));
  });

  it('rejeição com objeto {code, message} é normalizada sem virar "[object Object]"', async () => {
    const { firebaseAdmin, prisma, sensoryProfileService, send } = buildDeps();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', fcmToken: 'tok' });
    send.mockRejectedValue({ code: 'messaging/invalid-argument', message: 'token invalido' });
    const service = new NotificationService(firebaseAdmin as any, prisma as any, sensoryProfileService as any);

    await expect(service.notifyInboxAtualizada('u1')).resolves.toBeUndefined();

    expect(warnSpy).toHaveBeenCalledWith(expect.stringContaining('messaging/invalid-argument'));
    expect(warnSpy).toHaveBeenCalledWith(expect.stringContaining('token invalido'));
    expect(warnSpy).not.toHaveBeenCalledWith(expect.stringContaining('[object Object]'));
  });

  it('rejeição sem valor (Promise.reject()) loga "erro desconhecido" em vez de "undefined"', async () => {
    const { firebaseAdmin, prisma, sensoryProfileService, send } = buildDeps();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', fcmToken: 'tok' });
    send.mockRejectedValue(undefined);
    const service = new NotificationService(firebaseAdmin as any, prisma as any, sensoryProfileService as any);

    await expect(service.notifyInboxAtualizada('u1')).resolves.toBeUndefined();

    expect(warnSpy).toHaveBeenCalledWith(expect.stringContaining('erro desconhecido'));
    expect(warnSpy).not.toHaveBeenCalledWith(expect.stringContaining('undefined'));
  });
});
