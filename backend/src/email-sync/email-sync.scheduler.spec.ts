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
});
