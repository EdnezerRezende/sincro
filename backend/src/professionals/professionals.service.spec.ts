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

  describe('adminList', () => {
    it('returns all professionals including inactive ones, ordered by name', async () => {
      const prisma = buildPrismaMock();
      prisma.professional.findMany.mockResolvedValue([]);
      const service = new ProfessionalsService(prisma as any);

      await service.adminList();

      expect(prisma.professional.findMany).toHaveBeenCalledWith({ orderBy: { nome: 'asc' } });
    });
  });

  describe('create', () => {
    it('creates an active professional from the given data', async () => {
      const prisma = buildPrismaMock();
      prisma.professional.create.mockResolvedValue(buildProfessional());
      const service = new ProfessionalsService(prisma as any);
      const dto = {
        nome: 'Dra. Marina',
        tags: ['TEA'],
        cidade: 'São Paulo',
        latitude: -23.5,
        longitude: -46.6,
        telefone: '+5511999999999',
        bio: 'Bio',
      };

      await service.create(dto as any);

      expect(prisma.professional.create).toHaveBeenCalledWith({ data: { ...dto, ativo: true } });
    });
  });

  describe('update', () => {
    it('updates a professional by id with the given data', async () => {
      const prisma = buildPrismaMock();
      prisma.professional.update.mockResolvedValue(buildProfessional());
      const service = new ProfessionalsService(prisma as any);
      const dto = {
        nome: 'Novo nome',
        tags: ['TEA'],
        cidade: 'São Paulo',
        latitude: 0,
        longitude: 0,
        telefone: '+5511999999999',
        bio: 'Bio',
      };

      await service.update('p1', dto as any);

      expect(prisma.professional.update).toHaveBeenCalledWith({ where: { id: 'p1' }, data: dto });
    });
  });

  describe('deactivate', () => {
    it('soft-deletes by setting ativo to false', async () => {
      const prisma = buildPrismaMock();
      prisma.professional.update.mockResolvedValue(buildProfessional({ ativo: false }));
      const service = new ProfessionalsService(prisma as any);

      await service.deactivate('p1');

      expect(prisma.professional.update).toHaveBeenCalledWith({ where: { id: 'p1' }, data: { ativo: false } });
    });
  });
});
