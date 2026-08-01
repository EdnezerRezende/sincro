import { SensoryProfileService } from './sensory-profile.service';

describe('SensoryProfileService', () => {
  it('upserts the profile scoped to the resolved user id', async () => {
    const prisma = { sensoryProfile: { upsert: jest.fn().mockResolvedValue({ id: 'sp1' }) } };
    const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1' }) };
    const service = new SensoryProfileService(prisma as any, usersService as any);

    const dados = { toleranciaNotificacao: 'SILENCIOSAS' };
    await service.upsert('fb1', dados);

    expect(usersService.getByFirebaseUidOrThrow).toHaveBeenCalledWith('fb1');
    expect(prisma.sensoryProfile.upsert).toHaveBeenCalledWith({
      where: { userId: 'u1' },
      update: { dados },
      create: { userId: 'u1', dados },
    });
  });

  it('gets the profile scoped to the resolved user id', async () => {
    const prisma = { sensoryProfile: { findUnique: jest.fn().mockResolvedValue({ id: 'sp1' }) } };
    const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1' }) };
    const service = new SensoryProfileService(prisma as any, usersService as any);

    const result = await service.get('fb1');

    expect(prisma.sensoryProfile.findUnique).toHaveBeenCalledWith({ where: { userId: 'u1' } });
    expect(result).toEqual({ id: 'sp1' });
  });
});
