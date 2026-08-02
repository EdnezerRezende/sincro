import { GmailConnectionsService } from './gmail-connections.service';

function buildDeps() {
  const prisma = {
    gmailConnection: {
      upsert: jest.fn(),
      findUnique: jest.fn(),
      deleteMany: jest.fn(),
    },
    emailSummary: { deleteMany: jest.fn() },
  };
  const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1' }) };
  const tokenCrypto = {
    encrypt: jest.fn((v: string) => `encrypted(${v})`),
    decrypt: jest.fn((v: string) => v.replace('encrypted(', '').replace(')', '')),
  };
  const oauthService = {
    exchangeServerAuthCode: jest.fn().mockResolvedValue({ refreshToken: 'rt-123' }),
    getEmailAddress: jest.fn().mockResolvedValue('ana@example.com'),
    revoke: jest.fn().mockResolvedValue(undefined),
  };
  return { prisma, usersService, tokenCrypto, oauthService };
}

describe('GmailConnectionsService', () => {
  it('connects a new account, encrypting the refresh token before storing it', async () => {
    const { prisma, usersService, tokenCrypto, oauthService } = buildDeps();
    prisma.gmailConnection.upsert.mockResolvedValue({ id: 'gc1' });
    const service = new GmailConnectionsService(prisma as any, usersService as any, tokenCrypto as any, oauthService as any);

    await service.connect('fb1', 'auth-code-abc');

    expect(oauthService.exchangeServerAuthCode).toHaveBeenCalledWith('auth-code-abc');
    expect(tokenCrypto.encrypt).toHaveBeenCalledWith('rt-123');
    expect(prisma.gmailConnection.upsert).toHaveBeenCalledWith({
      where: { userId: 'u1' },
      update: { refreshTokenCriptografado: 'encrypted(rt-123)', gmailEmail: 'ana@example.com' },
      create: { userId: 'u1', refreshTokenCriptografado: 'encrypted(rt-123)', gmailEmail: 'ana@example.com' },
    });
  });

  it('reports connection status scoped to the resolved user', async () => {
    const { prisma, usersService, tokenCrypto, oauthService } = buildDeps();
    prisma.gmailConnection.findUnique.mockResolvedValue({ gmailEmail: 'ana@example.com' });
    const service = new GmailConnectionsService(prisma as any, usersService as any, tokenCrypto as any, oauthService as any);

    const status = await service.status('fb1');

    expect(prisma.gmailConnection.findUnique).toHaveBeenCalledWith({ where: { userId: 'u1' } });
    expect(status).toEqual({ connected: true, gmailEmail: 'ana@example.com' });
  });

  it('reports not connected when there is no row', async () => {
    const { prisma, usersService, tokenCrypto, oauthService } = buildDeps();
    prisma.gmailConnection.findUnique.mockResolvedValue(null);
    const service = new GmailConnectionsService(prisma as any, usersService as any, tokenCrypto as any, oauthService as any);

    const status = await service.status('fb1');

    expect(status).toEqual({ connected: false, gmailEmail: null });
  });

  it('disconnect revokes the token with Google and deletes both the connection and its summaries', async () => {
    const { prisma, usersService, tokenCrypto, oauthService } = buildDeps();
    prisma.gmailConnection.findUnique.mockResolvedValue({ refreshTokenCriptografado: 'encrypted(rt-123)' });
    const service = new GmailConnectionsService(prisma as any, usersService as any, tokenCrypto as any, oauthService as any);

    await service.disconnect('fb1');

    expect(oauthService.revoke).toHaveBeenCalledWith('rt-123');
    expect(prisma.emailSummary.deleteMany).toHaveBeenCalledWith({ where: { userId: 'u1' } });
    expect(prisma.gmailConnection.deleteMany).toHaveBeenCalledWith({ where: { userId: 'u1' } });
  });

  it('disconnect is a no-op-safe call when there is nothing to disconnect', async () => {
    const { prisma, usersService, tokenCrypto, oauthService } = buildDeps();
    prisma.gmailConnection.findUnique.mockResolvedValue(null);
    const service = new GmailConnectionsService(prisma as any, usersService as any, tokenCrypto as any, oauthService as any);

    await service.disconnect('fb1');

    expect(oauthService.revoke).not.toHaveBeenCalled();
    expect(prisma.gmailConnection.deleteMany).toHaveBeenCalledWith({ where: { userId: 'u1' } });
  });
});
