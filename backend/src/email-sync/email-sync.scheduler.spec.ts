import { EmailSyncScheduler } from './email-sync.scheduler';

describe('EmailSyncScheduler', () => {
  it('syncs every connected user and notifies when there are new attention-needing emails', async () => {
    const prisma = {
      gmailConnection: { findMany: jest.fn().mockResolvedValue([{ userId: 'u1' }, { userId: 'u2' }]) },
    };
    const emailSyncService = {
      syncUser: jest.fn().mockResolvedValueOnce({ novosPrecisamAtencao: 2 }).mockResolvedValueOnce({ novosPrecisamAtencao: 0 }),
    };
    const notificationService = { notifyNewEmailsNeedAttention: jest.fn() };
    const scheduler = new EmailSyncScheduler(prisma as any, emailSyncService as any, notificationService as any);

    await scheduler.syncAllConnectedUsers();

    expect(emailSyncService.syncUser).toHaveBeenNthCalledWith(1, 'u1');
    expect(emailSyncService.syncUser).toHaveBeenNthCalledWith(2, 'u2');
    expect(notificationService.notifyNewEmailsNeedAttention).toHaveBeenCalledTimes(1);
    expect(notificationService.notifyNewEmailsNeedAttention).toHaveBeenCalledWith('u1', 2);
  });

  it('keeps syncing remaining users when one user sync throws', async () => {
    const prisma = { gmailConnection: { findMany: jest.fn().mockResolvedValue([{ userId: 'u1' }, { userId: 'u2' }]) } };
    const emailSyncService = {
      syncUser: jest.fn().mockRejectedValueOnce(new Error('boom')).mockResolvedValueOnce({ novosPrecisamAtencao: 1 }),
    };
    const notificationService = { notifyNewEmailsNeedAttention: jest.fn() };
    const scheduler = new EmailSyncScheduler(prisma as any, emailSyncService as any, notificationService as any);

    await scheduler.syncAllConnectedUsers();

    expect(emailSyncService.syncUser).toHaveBeenCalledTimes(2);
    expect(notificationService.notifyNewEmailsNeedAttention).toHaveBeenCalledWith('u2', 1);
  });

  it('does not run two syncs concurrently when a cron firing overlaps a still-running previous one', async () => {
    const prisma = { gmailConnection: { findMany: jest.fn().mockResolvedValue([{ userId: 'u1' }]) } };
    let resolveSync!: (value: { novosPrecisamAtencao: number }) => void;
    const inFlight = new Promise<{ novosPrecisamAtencao: number }>((resolve) => {
      resolveSync = resolve;
    });
    const emailSyncService = { syncUser: jest.fn().mockReturnValue(inFlight) };
    const notificationService = { notifyNewEmailsNeedAttention: jest.fn() };
    const scheduler = new EmailSyncScheduler(prisma as any, emailSyncService as any, notificationService as any);

    const firstRun = scheduler.syncAllConnectedUsers();
    const secondRun = scheduler.syncAllConnectedUsers();

    resolveSync({ novosPrecisamAtencao: 0 });
    await Promise.all([firstRun, secondRun]);

    expect(prisma.gmailConnection.findMany).toHaveBeenCalledTimes(1);
    expect(emailSyncService.syncUser).toHaveBeenCalledTimes(1);
  });

  it('allows a later cron firing to run normally once the previous run has finished', async () => {
    const prisma = { gmailConnection: { findMany: jest.fn().mockResolvedValue([{ userId: 'u1' }]) } };
    const emailSyncService = { syncUser: jest.fn().mockResolvedValue({ novosPrecisamAtencao: 0 }) };
    const notificationService = { notifyNewEmailsNeedAttention: jest.fn() };
    const scheduler = new EmailSyncScheduler(prisma as any, emailSyncService as any, notificationService as any);

    await scheduler.syncAllConnectedUsers();
    await scheduler.syncAllConnectedUsers();

    expect(prisma.gmailConnection.findMany).toHaveBeenCalledTimes(2);
    expect(emailSyncService.syncUser).toHaveBeenCalledTimes(2);
  });
});
