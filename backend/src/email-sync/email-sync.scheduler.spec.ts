// @nestjs/event-emitter 12 é publicado só como ESM, que o ts-jest (CommonJS) não carrega. O
// decorador @OnEvent não tem efeito fora do contêiner do Nest, então basta um substituto vazio.
jest.mock('@nestjs/event-emitter', () => ({ OnEvent: () => () => undefined }));

import { EmailSyncScheduler } from './email-sync.scheduler';
import { EmailSyncLockService } from './email-sync-lock.service';

function build(userIds: string[], syncUser: jest.Mock) {
  const prisma = {
    gmailConnection: {
      findMany: jest
        .fn()
        .mockResolvedValue(userIds.map((userId) => ({ userId }))),
    },
  };
  const emailSyncService = { syncUser };
  const notificationService = { notifyNewEmailsNeedAttention: jest.fn() };
  const lockService = new EmailSyncLockService();
  const scheduler = new EmailSyncScheduler(
    prisma as any,
    emailSyncService as any,
    lockService,
    notificationService as any,
  );
  return {
    prisma,
    emailSyncService,
    notificationService,
    lockService,
    scheduler,
  };
}

describe('EmailSyncScheduler', () => {
  it('syncs every connected user and notifies when there are new attention-needing emails', async () => {
    const { scheduler, emailSyncService, notificationService } = build(
      ['u1', 'u2'],
      jest
        .fn()
        .mockResolvedValueOnce({ novos: 3, novosPrecisamAtencao: 2 })
        .mockResolvedValueOnce({ novos: 1, novosPrecisamAtencao: 0 }),
    );

    await scheduler.syncRapid();

    expect(emailSyncService.syncUser).toHaveBeenNthCalledWith(1, 'u1');
    expect(emailSyncService.syncUser).toHaveBeenNthCalledWith(2, 'u2');
    expect(
      notificationService.notifyNewEmailsNeedAttention,
    ).toHaveBeenCalledTimes(1);
    expect(
      notificationService.notifyNewEmailsNeedAttention,
    ).toHaveBeenCalledWith('u1', 2);
  });

  it('keeps syncing remaining users when one user sync throws', async () => {
    const { scheduler, emailSyncService, notificationService } = build(
      ['u1', 'u2'],
      jest
        .fn()
        .mockRejectedValueOnce(new Error('boom'))
        .mockResolvedValueOnce({ novos: 1, novosPrecisamAtencao: 1 }),
    );

    await scheduler.syncRapid();

    expect(emailSyncService.syncUser).toHaveBeenCalledTimes(2);
    expect(
      notificationService.notifyNewEmailsNeedAttention,
    ).toHaveBeenCalledWith('u2', 1);
  });

  it('skips a user whose previous sync is still running when a cron firing overlaps', async () => {
    let resolveSync!: (value: {
      novos: number;
      novosPrecisamAtencao: number;
    }) => void;
    const inFlight = new Promise<{
      novos: number;
      novosPrecisamAtencao: number;
    }>((resolve) => {
      resolveSync = resolve;
    });
    const { scheduler, emailSyncService } = build(
      ['u1'],
      jest.fn().mockReturnValue(inFlight),
    );

    const firstRun = scheduler.syncRapid();
    // Deixa a primeira execução chegar até a chamada de syncUser (e pegar o lock do usuário).
    await new Promise((r) => setImmediate(r));
    const secondRun = scheduler.syncRapid();

    resolveSync({ novos: 0, novosPrecisamAtencao: 0 });
    await Promise.all([firstRun, secondRun]);

    expect(emailSyncService.syncUser).toHaveBeenCalledTimes(1);
  });

  it('allows a later cron firing to run normally once the previous run has finished', async () => {
    const { scheduler, emailSyncService } = build(
      ['u1'],
      jest.fn().mockResolvedValue({ novos: 0, novosPrecisamAtencao: 0 }),
    );

    await scheduler.syncRapid();
    await scheduler.syncRapid();

    expect(emailSyncService.syncUser).toHaveBeenCalledTimes(2);
  });

  it('runs an initial sync for the user when the gmail.conectado event fires', async () => {
    const { scheduler, emailSyncService } = build(
      [],
      jest.fn().mockResolvedValue({ novos: 5, novosPrecisamAtencao: 1 }),
    );

    await scheduler.onGmailConnected({ userId: 'u9' });

    expect(emailSyncService.syncUser).toHaveBeenCalledWith('u9');
  });
});
