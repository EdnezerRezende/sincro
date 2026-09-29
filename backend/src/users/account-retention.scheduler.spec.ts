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

  it('keeps a user who signed in long ago but kept using the app (recent lastRefreshTime)', async () => {
    // Regressão: o app mantém a sessão por meses, então lastSignInTime só reflete o login
    // original. Quem usa o app todo dia tem lastRefreshTime recente e não pode ser apagado.
    const agora = Date.now();
    const prisma = {
      user: {
        findMany: jest.fn().mockResolvedValue([
          {
            firebaseUid: 'usa-todo-dia',
            createdAt: new Date(agora - 300 * DIA_MS),
          },
          { firebaseUid: 'sumiu', createdAt: new Date(agora - 300 * DIA_MS) },
        ]),
      },
    };
    const firebaseAdmin = buildFirebaseAdmin(() => ({
      users: [
        {
          uid: 'usa-todo-dia',
          metadata: {
            lastSignInTime: new Date(agora - 200 * DIA_MS).toUTCString(),
            lastRefreshTime: new Date(agora - 1 * DIA_MS).toUTCString(),
          },
        },
        {
          uid: 'sumiu',
          metadata: {
            lastSignInTime: new Date(agora - 200 * DIA_MS).toUTCString(),
            lastRefreshTime: new Date(agora - 120 * DIA_MS).toUTCString(),
          },
        },
      ],
      notFound: [],
    }));
    const usersService = { deleteAccount: jest.fn() };
    const scheduler = new AccountRetentionScheduler(
      prisma as any,
      usersService as any,
      firebaseAdmin as any,
    );

    await scheduler.purgeInactiveAccounts();

    expect(usersService.deleteAccount).toHaveBeenCalledTimes(1);
    expect(usersService.deleteAccount).toHaveBeenCalledWith('sumiu');
  });

  it('uses the most recent of lastSignInTime and lastRefreshTime (fresh sign-in, stale refresh)', async () => {
    const agora = Date.now();
    const prisma = {
      user: {
        findMany: jest.fn().mockResolvedValue([
          {
            firebaseUid: 'login-recente',
            createdAt: new Date(agora - 300 * DIA_MS),
          },
        ]),
      },
    };
    const firebaseAdmin = buildFirebaseAdmin(() => ({
      users: [
        {
          uid: 'login-recente',
          metadata: {
            lastSignInTime: new Date(agora - 2 * DIA_MS).toUTCString(),
            lastRefreshTime: new Date(agora - 120 * DIA_MS).toUTCString(),
          },
        },
      ],
      notFound: [],
    }));
    const usersService = { deleteAccount: jest.fn() };
    const scheduler = new AccountRetentionScheduler(
      prisma as any,
      usersService as any,
      firebaseAdmin as any,
    );

    await scheduler.purgeInactiveAccounts();

    expect(usersService.deleteAccount).not.toHaveBeenCalled();
  });

  it('ignores an unparseable timestamp instead of letting it hide a recent one', async () => {
    const agora = Date.now();
    const prisma = {
      user: {
        findMany: jest.fn().mockResolvedValue([
          { firebaseUid: 'data-invalida', createdAt: new Date(agora - 300 * DIA_MS) },
        ]),
      },
    };
    const firebaseAdmin = buildFirebaseAdmin(() => ({
      users: [
        {
          uid: 'data-invalida',
          metadata: {
            lastSignInTime: 'não é uma data',
            lastRefreshTime: new Date(agora - 2 * DIA_MS).toUTCString(),
          },
        },
      ],
      notFound: [],
    }));
    const usersService = { deleteAccount: jest.fn() };
    const scheduler = new AccountRetentionScheduler(prisma as any, usersService as any, firebaseAdmin as any);

    await scheduler.purgeInactiveAccounts();

    expect(usersService.deleteAccount).not.toHaveBeenCalled();
  });

  it('falls back to createdAt when the Firebase record comes without metadata', async () => {
    const agora = Date.now();
    const prisma = {
      user: {
        findMany: jest.fn().mockResolvedValue([
          { firebaseUid: 'sem-metadata-novo', createdAt: new Date(agora - 5 * DIA_MS) },
          { firebaseUid: 'sem-metadata-antigo', createdAt: new Date(agora - 300 * DIA_MS) },
        ]),
      },
    };
    const firebaseAdmin = buildFirebaseAdmin(() => ({
      users: [{ uid: 'sem-metadata-novo' }, { uid: 'sem-metadata-antigo' }],
      notFound: [],
    }));
    const usersService = { deleteAccount: jest.fn() };
    const scheduler = new AccountRetentionScheduler(prisma as any, usersService as any, firebaseAdmin as any);

    await expect(scheduler.purgeInactiveAccounts()).resolves.toBeUndefined();

    expect(usersService.deleteAccount).toHaveBeenCalledTimes(1);
    expect(usersService.deleteAccount).toHaveBeenCalledWith('sem-metadata-antigo');
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
