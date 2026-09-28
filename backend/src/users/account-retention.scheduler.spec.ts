import { AccountRetentionScheduler } from './account-retention.scheduler';

const DIA_MS = 24 * 60 * 60 * 1000;

function buildFirebaseAdmin(getUsersImpl: (...args: any[]) => any) {
  return { auth: jest.fn().mockReturnValue({ getUsers: jest.fn(getUsersImpl) }) };
}

describe('AccountRetentionScheduler', () => {
  it('deletes accounts whose Firebase lastSignInTime is 90+ days old and keeps recent ones', async () => {
    const agora = Date.now();
    const antigo = new Date(agora - 91 * DIA_MS).toUTCString();
    const recente = new Date(agora - 10 * DIA_MS).toUTCString();
    const prisma = {
      user: {
        findMany: jest.fn().mockResolvedValue([
          { firebaseUid: 'inativo', createdAt: new Date(agora - 200 * DIA_MS) },
          { firebaseUid: 'ativo', createdAt: new Date(agora - 200 * DIA_MS) },
        ]),
      },
    };
    const firebaseAdmin = buildFirebaseAdmin(() => ({
      users: [
        { uid: 'inativo', metadata: { lastSignInTime: antigo } },
        { uid: 'ativo', metadata: { lastSignInTime: recente } },
      ],
      notFound: [],
    }));
    const usersService = { deleteAccount: jest.fn() };
    const scheduler = new AccountRetentionScheduler(prisma as any, usersService as any, firebaseAdmin as any);

    await scheduler.purgeInactiveAccounts();

    expect(usersService.deleteAccount).toHaveBeenCalledTimes(1);
    expect(usersService.deleteAccount).toHaveBeenCalledWith('inativo');
  });

  it('treats a user with no matching Firebase Auth record (orphaned row) as eligible', async () => {
    const prisma = {
      user: {
        findMany: jest.fn().mockResolvedValue([
          { firebaseUid: 'orfao', createdAt: new Date(Date.now() - 200 * DIA_MS) },
        ]),
      },
    };
    const firebaseAdmin = buildFirebaseAdmin(() => ({ users: [], notFound: [{ uid: 'orfao' }] }));
    const usersService = { deleteAccount: jest.fn() };
    const scheduler = new AccountRetentionScheduler(prisma as any, usersService as any, firebaseAdmin as any);

    await scheduler.purgeInactiveAccounts();

    expect(usersService.deleteAccount).toHaveBeenCalledWith('orfao');
  });

  it('uses createdAt as the activity fallback when the Firebase record has no lastSignInTime yet', async () => {
    const prisma = {
      user: {
        findMany: jest.fn().mockResolvedValue([
          { firebaseUid: 'recente-sem-login', createdAt: new Date(Date.now() - 5 * DIA_MS) },
        ]),
      },
    };
    const firebaseAdmin = buildFirebaseAdmin(() => ({
      users: [{ uid: 'recente-sem-login', metadata: { lastSignInTime: null } }],
      notFound: [],
    }));
    const usersService = { deleteAccount: jest.fn() };
    const scheduler = new AccountRetentionScheduler(prisma as any, usersService as any, firebaseAdmin as any);

    await scheduler.purgeInactiveAccounts();

    expect(usersService.deleteAccount).not.toHaveBeenCalled();
  });

  it('does nothing when there are no users', async () => {
    const prisma = { user: { findMany: jest.fn().mockResolvedValue([]) } };
    const firebaseAdmin = buildFirebaseAdmin(() => ({ users: [], notFound: [] }));
    const usersService = { deleteAccount: jest.fn() };
    const scheduler = new AccountRetentionScheduler(prisma as any, usersService as any, firebaseAdmin as any);

    await scheduler.purgeInactiveAccounts();

    expect(firebaseAdmin.auth).not.toHaveBeenCalled();
    expect(usersService.deleteAccount).not.toHaveBeenCalled();
  });

  it('skips the batch (deletes nobody in it) when the Firebase lookup itself fails', async () => {
    const prisma = {
      user: {
        findMany: jest.fn().mockResolvedValue([
          { firebaseUid: 'qualquer', createdAt: new Date(Date.now() - 300 * DIA_MS) },
        ]),
      },
    };
    const firebaseAdmin = buildFirebaseAdmin(() => {
      throw new Error('Firebase indisponível');
    });
    const usersService = { deleteAccount: jest.fn() };
    const scheduler = new AccountRetentionScheduler(prisma as any, usersService as any, firebaseAdmin as any);

    await expect(scheduler.purgeInactiveAccounts()).resolves.toBeUndefined();

    expect(usersService.deleteAccount).not.toHaveBeenCalled();
  });

  it('keeps processing other overdue accounts when deleting one of them throws', async () => {
    const antigo = new Date(Date.now() - 200 * DIA_MS).toUTCString();
    const prisma = {
      user: {
        findMany: jest.fn().mockResolvedValue([
          { firebaseUid: 'falha', createdAt: new Date(Date.now() - 200 * DIA_MS) },
          { firebaseUid: 'ok', createdAt: new Date(Date.now() - 200 * DIA_MS) },
        ]),
      },
    };
    const firebaseAdmin = buildFirebaseAdmin(() => ({
      users: [
        { uid: 'falha', metadata: { lastSignInTime: antigo } },
        { uid: 'ok', metadata: { lastSignInTime: antigo } },
      ],
      notFound: [],
    }));
    const usersService = {
      deleteAccount: jest.fn().mockRejectedValueOnce(new Error('boom')).mockResolvedValueOnce(undefined),
    };
    const scheduler = new AccountRetentionScheduler(prisma as any, usersService as any, firebaseAdmin as any);

    await scheduler.purgeInactiveAccounts();

    expect(usersService.deleteAccount).toHaveBeenCalledTimes(2);
    expect(usersService.deleteAccount).toHaveBeenCalledWith('falha');
    expect(usersService.deleteAccount).toHaveBeenCalledWith('ok');
  });

  it('batches Firebase lookups in groups of at most 100 identifiers', async () => {
    const antigo = new Date(Date.now() - 200 * DIA_MS).toUTCString();
    const usuarios = Array.from({ length: 150 }, (_, i) => ({
      firebaseUid: `u${i}`,
      createdAt: new Date(Date.now() - 200 * DIA_MS),
    }));
    const prisma = { user: { findMany: jest.fn().mockResolvedValue(usuarios) } };
    const getUsers = jest.fn().mockImplementation((identifiers: { uid: string }[]) => ({
      users: identifiers.map(({ uid }) => ({ uid, metadata: { lastSignInTime: antigo } })),
      notFound: [],
    }));
    const firebaseAdmin = { auth: jest.fn().mockReturnValue({ getUsers }) };
    const usersService = { deleteAccount: jest.fn() };
    const scheduler = new AccountRetentionScheduler(prisma as any, usersService as any, firebaseAdmin as any);

    await scheduler.purgeInactiveAccounts();

    expect(getUsers).toHaveBeenCalledTimes(2);
    expect(getUsers.mock.calls[0][0]).toHaveLength(100);
    expect(getUsers.mock.calls[1][0]).toHaveLength(50);
    expect(usersService.deleteAccount).toHaveBeenCalledTimes(150);
  });
});
