import { ProfessionalsService } from './professionals.service';

function buildPrismaMock() {
  return {
    professional: {
      findMany: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
    },
  };
}

function buildProfessional(overrides: Partial<any> = {}) {
  return {
    id: 'p1',
    nome: 'Dra. Marina',
    tags: [],
    cidade: 'São Paulo',
    latitude: 0,
    longitude: 0,
    telefone: '+5511999999999',
    bio: 'Bio',
    ativo: true,
    ...overrides,
  };
}

describe('ProfessionalsService', () => {
  describe('search', () => {
    it('sorts active professionals by distance to the given coordinates', async () => {
      const prisma = buildPrismaMock();
      prisma.professional.findMany.mockResolvedValue([
        buildProfessional({ id: 'p-longe', latitude: 0, longitude: 10 }),
        buildProfessional({ id: 'p-perto', latitude: 0, longitude: 1 }),
      ]);
      const service = new ProfessionalsService(prisma as any);

      const result = await service.search(0, 0);

      expect(prisma.professional.findMany).toHaveBeenCalledWith({ where: { ativo: true } });
      expect(result.map((p) => p.id)).toEqual(['p-perto', 'p-longe']);
      expect(result[0].distanciaKm).toBeLessThan(result[1].distanciaKm);
    });

    it('filters by tags using hasSome (any-match) semantics', async () => {
      const prisma = buildPrismaMock();
      prisma.professional.findMany.mockResolvedValue([]);
      const service = new ProfessionalsService(prisma as any);

      await service.search(0, 0, ['TEA', 'TDAH']);

      expect(prisma.professional.findMany).toHaveBeenCalledWith({
        where: { ativo: true, tags: { hasSome: ['TEA', 'TDAH'] } },
      });
    });
  });

  describe('listActiveTags', () => {
    it('returns the deduplicated, sorted set of tags among active professionals', async () => {
      const prisma = buildPrismaMock();
      prisma.professional.findMany.mockResolvedValue([{ tags: ['TDAH', 'TEA'] }, { tags: ['TEA', 'Ansiedade'] }]);
      const service = new ProfessionalsService(prisma as any);

      const tags = await service.listActiveTags();

      expect(tags).toEqual(['Ansiedade', 'TDAH', 'TEA']);
      expect(prisma.professional.findMany).toHaveBeenCalledWith({ where: { ativo: true }, select: { tags: true } });
    });
  });
});
