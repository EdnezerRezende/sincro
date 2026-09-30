import { NotFoundException } from '@nestjs/common';
import { UsersService } from './users.service';

function buildPrismaMock() {
  return {
    user: {
      upsert: jest.fn(),
      findUnique: jest.fn(),
      update: jest.fn(),
      delete: jest.fn(),
    },
    sensoryProfile: { findUnique: jest.fn(), deleteMany: jest.fn() },
    trustedContact: { count: jest.fn(), deleteMany: jest.fn() },
    cardFavorito: { deleteMany: jest.fn() },
    whatsappMensagem: { deleteMany: jest.fn() },
    whatsappConversaEstado: { deleteMany: jest.fn() },
    whatsappVinculo: { deleteMany: jest.fn() },
    lancamentoFinanceiro: { deleteMany: jest.fn() },
    contaFinanceira: { deleteMany: jest.fn() },
    cartaoCredito: { deleteMany: jest.fn() },
    // Simula o comportamento real de `$transaction(ops[])`: aguarda todas as operações.
    $transaction: jest.fn((ops: Promise<unknown>[]) => Promise.all(ops)),
  };
}

function buildGmailConnectionsServiceMock() {
  return { disconnect: jest.fn() };
}

function buildFirebaseAdminMock() {
  return { auth: jest.fn().mockReturnValue({ deleteUser: jest.fn() }) };
}

/** Constrói o serviço com dependências extras mockadas por padrão — só `prisma` costuma
 *  importar para a maioria dos testes já existentes. */
function buildService(
  prisma: any,
  gmailConnectionsService = buildGmailConnectionsServiceMock(),
  firebaseAdmin = buildFirebaseAdminMock(),
) {
  return new UsersService(
    prisma,
    gmailConnectionsService as any,
    firebaseAdmin as any,
  );
}

describe('UsersService', () => {
  it('upserts a user by firebaseUid', async () => {
    const prisma = buildPrismaMock();
    prisma.user.upsert.mockResolvedValue({
      id: 'u1',
      firebaseUid: 'fb1',
      nome: 'Ana',
    });
    const service = buildService(prisma);

    const result = await service.upsertByFirebaseUid('fb1', 'Ana');

    expect(prisma.user.upsert).toHaveBeenCalledWith({
      where: { firebaseUid: 'fb1' },
      update: { nome: 'Ana' },
      create: { firebaseUid: 'fb1', nome: 'Ana' },
    });
    expect(result.nome).toBe('Ana');
  });

  it('throws NotFoundException when the user does not exist yet', async () => {
    const prisma = buildPrismaMock();
    prisma.user.findUnique.mockResolvedValue(null);
    const service = buildService(prisma);

    await expect(service.getByFirebaseUidOrThrow('missing')).rejects.toThrow(
      NotFoundException,
    );
  });

  it('builds onboarding status combining profile and contact count', async () => {
    const prisma = buildPrismaMock();
    prisma.user.findUnique.mockResolvedValue({
      id: 'u1',
      firebaseUid: 'fb1',
      nome: 'Ana',
      diaRecebimento: 5,
      isAdmin: false,
    });
    prisma.sensoryProfile.findUnique.mockResolvedValue({ id: 'sp1' });
    prisma.trustedContact.count.mockResolvedValue(2);
    const service = buildService(prisma);

    const status = await service.getOnboardingStatus('fb1');

    expect(status).toEqual({
      userId: 'u1',
      nome: 'Ana',
      hasSensoryProfile: true,
      trustedContactCount: 2,
      diaRecebimento: 5,
      isAdmin: false,
    });
  });

  it('exposes a null diaRecebimento when the user never set one', async () => {
    const prisma = buildPrismaMock();
    prisma.user.findUnique.mockResolvedValue({
      id: 'u1',
      firebaseUid: 'fb1',
      nome: 'Ana',
      diaRecebimento: null,
      isAdmin: false,
    });
    prisma.sensoryProfile.findUnique.mockResolvedValue(null);
    prisma.trustedContact.count.mockResolvedValue(0);
    const service = buildService(prisma);

    const status = await service.getOnboardingStatus('fb1');

    expect(status.diaRecebimento).toBeNull();
  });

  it('exposes isAdmin true for an admin user', async () => {
    const prisma = buildPrismaMock();
    prisma.user.findUnique.mockResolvedValue({
      id: 'u1',
      firebaseUid: 'fb1',
      nome: 'Ana',
      diaRecebimento: null,
      isAdmin: true,
    });
    prisma.sensoryProfile.findUnique.mockResolvedValue(null);
    prisma.trustedContact.count.mockResolvedValue(0);
    const service = buildService(prisma);

    const status = await service.getOnboardingStatus('fb1');

    expect(status.isAdmin).toBe(true);
  });

  it('registers an fcm token for the resolved user', async () => {
    const prisma = buildPrismaMock();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1' });
    prisma.user.update = jest.fn();
    const service = buildService(prisma);

    await service.registerFcmToken('fb1', 'token-xyz');

    expect(prisma.user.update).toHaveBeenCalledWith({
      where: { id: 'u1' },
      data: { fcmToken: 'token-xyz' },
    });
  });

  describe('updateDiaRecebimento', () => {
    it('updates the resolved user with the given day', async () => {
      const prisma = {
        user: {
          findUnique: jest.fn().mockResolvedValue({ id: 'u1' }),
          update: jest.fn(),
        },
      };
      const service = buildService(prisma);

      await service.updateDiaRecebimento('fb1', 15);

      expect(prisma.user.update).toHaveBeenCalledWith({
        where: { id: 'u1' },
        data: { diaRecebimento: 15 },
      });
    });

    it('allows clearing the day by passing null', async () => {
      const prisma = {
        user: {
          findUnique: jest.fn().mockResolvedValue({ id: 'u1' }),
          update: jest.fn(),
        },
      };
      const service = buildService(prisma);

      await service.updateDiaRecebimento('fb1', null);

      expect(prisma.user.update).toHaveBeenCalledWith({
        where: { id: 'u1' },
        data: { diaRecebimento: null },
      });
    });
  });

  describe('deleteAccount', () => {
    it('disconnects Gmail, deletes every owned row in one transaction, then the Firebase user', async () => {
      const prisma = buildPrismaMock();
      prisma.user.findUnique.mockResolvedValue({
        id: 'u1',
        firebaseUid: 'fb1',
      });
      const gmailConnectionsService = buildGmailConnectionsServiceMock();
      const firebaseAdmin = buildFirebaseAdminMock();
      const service = buildService(
        prisma,
        gmailConnectionsService,
        firebaseAdmin,
      );

      await service.deleteAccount('fb1');

      expect(gmailConnectionsService.disconnect).toHaveBeenCalledWith('fb1');
      expect(prisma.sensoryProfile.deleteMany).toHaveBeenCalledWith({
        where: { userId: 'u1' },
      });
      expect(prisma.trustedContact.deleteMany).toHaveBeenCalledWith({
        where: { userId: 'u1' },
      });
      expect(prisma.cardFavorito.deleteMany).toHaveBeenCalledWith({
        where: { userId: 'u1' },
      });
      expect(prisma.whatsappMensagem.deleteMany).toHaveBeenCalledWith({
        where: { userId: 'u1' },
      });
      expect(prisma.whatsappConversaEstado.deleteMany).toHaveBeenCalledWith({
        where: { userId: 'u1' },
      });
      expect(prisma.whatsappVinculo.deleteMany).toHaveBeenCalledWith({
        where: { userId: 'u1' },
      });
      expect(prisma.lancamentoFinanceiro.deleteMany).toHaveBeenCalledWith({
        where: { userId: 'u1' },
      });
      expect(prisma.contaFinanceira.deleteMany).toHaveBeenCalledWith({
        where: { userId: 'u1' },
      });
      expect(prisma.cartaoCredito.deleteMany).toHaveBeenCalledWith({
        where: { userId: 'u1' },
      });
      expect(prisma.user.delete).toHaveBeenCalledWith({ where: { id: 'u1' } });
      expect(prisma.$transaction).toHaveBeenCalledTimes(1);
      expect(firebaseAdmin.auth().deleteUser).toHaveBeenCalledWith('fb1');
    });

    it('throws NotFoundException instead of deleting anything when the user row does not exist', async () => {
      const prisma = buildPrismaMock();
      prisma.user.findUnique.mockResolvedValue(null);
      const gmailConnectionsService = buildGmailConnectionsServiceMock();
      const service = buildService(prisma, gmailConnectionsService);

      await expect(service.deleteAccount('missing')).rejects.toThrow(
        NotFoundException,
      );

      expect(gmailConnectionsService.disconnect).not.toHaveBeenCalled();
      expect(prisma.$transaction).not.toHaveBeenCalled();
    });

    it('still completes when revoking/deleting the Firebase Auth user fails (DB cleanup already committed)', async () => {
      const prisma = buildPrismaMock();
      prisma.user.findUnique.mockResolvedValue({
        id: 'u1',
        firebaseUid: 'fb1',
      });
      const firebaseAdmin = {
        auth: jest.fn().mockReturnValue({
          deleteUser: jest.fn().mockRejectedValue(new Error('user-not-found')),
        }),
      };
      const service = buildService(
        prisma,
        buildGmailConnectionsServiceMock(),
        firebaseAdmin,
      );

      await expect(service.deleteAccount('fb1')).resolves.toBeUndefined();

      expect(prisma.user.delete).toHaveBeenCalledWith({ where: { id: 'u1' } });
    });
  });
});

describe('UsersService.getFeatureFlags', () => {
  const originalEnv = process.env;
  afterEach(() => {
    process.env = originalEnv;
  });

  it('resolves the flags from the user plan', async () => {
    process.env = { ...originalEnv, ADS_ENABLED: 'true' };
    const prisma = buildPrismaMock();
    prisma.user.findUnique.mockResolvedValue({
      id: 'u1',
      firebaseUid: 'fb1',
      plano: 'pro',
    });
    const service = new UsersService(prisma as any, {} as any, {} as any);

    const flags = await service.getFeatureFlags('fb1');

    expect(flags.plano).toBe('pro');
    expect(flags.ads.enabled).toBe(false);
  });
});
