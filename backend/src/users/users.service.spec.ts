import { NotFoundException } from '@nestjs/common';
import { UsersService } from './users.service';

function buildPrismaMock() {
  return {
    user: { upsert: jest.fn(), findUnique: jest.fn() },
    sensoryProfile: { findUnique: jest.fn() },
    trustedContact: { count: jest.fn() },
  };
}

describe('UsersService', () => {
  it('upserts a user by firebaseUid', async () => {
    const prisma = buildPrismaMock();
    prisma.user.upsert.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', nome: 'Ana' });
    const service = new UsersService(prisma as any);

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
    const service = new UsersService(prisma as any);

    await expect(service.getByFirebaseUidOrThrow('missing')).rejects.toThrow(NotFoundException);
  });

  it('builds onboarding status combining profile and contact count', async () => {
    const prisma = buildPrismaMock();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', nome: 'Ana', diaRecebimento: 5 });
    prisma.sensoryProfile.findUnique.mockResolvedValue({ id: 'sp1' });
    prisma.trustedContact.count.mockResolvedValue(2);
    const service = new UsersService(prisma as any);

    const status = await service.getOnboardingStatus('fb1');

    expect(status).toEqual({
      userId: 'u1',
      nome: 'Ana',
      hasSensoryProfile: true,
      trustedContactCount: 2,
      diaRecebimento: 5,
    });
  });

  it('exposes a null diaRecebimento when the user never set one', async () => {
    const prisma = buildPrismaMock();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', nome: 'Ana', diaRecebimento: null });
    prisma.sensoryProfile.findUnique.mockResolvedValue(null);
    prisma.trustedContact.count.mockResolvedValue(0);
    const service = new UsersService(prisma as any);

    const status = await service.getOnboardingStatus('fb1');

    expect(status.diaRecebimento).toBeNull();
  });

  it('registers an fcm token for the resolved user', async () => {
    const prisma = buildPrismaMock();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1' });
    prisma.user.update = jest.fn();
    const service = new UsersService(prisma as any);

    await service.registerFcmToken('fb1', 'token-xyz');

    expect(prisma.user.update).toHaveBeenCalledWith({ where: { id: 'u1' }, data: { fcmToken: 'token-xyz' } });
  });

  describe('updateDiaRecebimento', () => {
    it('updates the resolved user with the given day', async () => {
      const prisma = { user: { findUnique: jest.fn().mockResolvedValue({ id: 'u1' }), update: jest.fn() } };
      const service = new UsersService(prisma as any);

      await service.updateDiaRecebimento('fb1', 15);

      expect(prisma.user.update).toHaveBeenCalledWith({ where: { id: 'u1' }, data: { diaRecebimento: 15 } });
    });

    it('allows clearing the day by passing null', async () => {
      const prisma = { user: { findUnique: jest.fn().mockResolvedValue({ id: 'u1' }), update: jest.fn() } };
      const service = new UsersService(prisma as any);

      await service.updateDiaRecebimento('fb1', null);

      expect(prisma.user.update).toHaveBeenCalledWith({ where: { id: 'u1' }, data: { diaRecebimento: null } });
    });
  });
});
