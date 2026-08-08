import { GroundingCardsService } from './grounding-cards.service';

function buildPrismaMock() {
  return {
    groundingCard: { findMany: jest.fn(), create: jest.fn(), update: jest.fn() },
    cardFavorito: { findMany: jest.fn(), upsert: jest.fn(), deleteMany: jest.fn() },
  };
}

function buildCard(overrides: Partial<any> = {}) {
  return {
    id: 'c1',
    titulo: 'Respiração 4-7-8',
    categoria: 'RESPIRACAO',
    conteudo: 'Inspire por 4 segundos, segure por 7, expire por 8.',
    ativo: true,
    ...overrides,
  };
}

describe('GroundingCardsService', () => {
  describe('list', () => {
    it('returns only active cards when no categoria is given', async () => {
      const prisma = buildPrismaMock();
      prisma.groundingCard.findMany.mockResolvedValue([buildCard()]);
      const service = new GroundingCardsService(prisma as any);

      await service.list();

      expect(prisma.groundingCard.findMany).toHaveBeenCalledWith({
        where: { ativo: true },
        orderBy: { titulo: 'asc' },
      });
    });

    it('filters by categoria when given', async () => {
      const prisma = buildPrismaMock();
      prisma.groundingCard.findMany.mockResolvedValue([]);
      const service = new GroundingCardsService(prisma as any);

      await service.list('RESPIRACAO');

      expect(prisma.groundingCard.findMany).toHaveBeenCalledWith({
        where: { ativo: true, categoria: 'RESPIRACAO' },
        orderBy: { titulo: 'asc' },
      });
    });
  });

  describe('listFavoritos', () => {
    it('returns only active favorited cards for the given user', async () => {
      const prisma = buildPrismaMock();
      prisma.cardFavorito.findMany.mockResolvedValue([
        { card: buildCard({ id: 'c1', ativo: true }) },
        { card: buildCard({ id: 'c2', ativo: false }) },
      ]);
      const service = new GroundingCardsService(prisma as any);

      const result = await service.listFavoritos('u1');

      expect(prisma.cardFavorito.findMany).toHaveBeenCalledWith({
        where: { userId: 'u1' },
        include: { card: true },
      });
      expect(result.map((c) => c.id)).toEqual(['c1']);
    });
  });

  describe('favoritar', () => {
    it('upserts the favorite so favoriting twice does not duplicate', async () => {
      const prisma = buildPrismaMock();
      prisma.cardFavorito.upsert.mockResolvedValue({});
      const service = new GroundingCardsService(prisma as any);

      await service.favoritar('u1', 'c1');

      expect(prisma.cardFavorito.upsert).toHaveBeenCalledWith({
        where: { userId_cardId: { userId: 'u1', cardId: 'c1' } },
        update: {},
        create: { userId: 'u1', cardId: 'c1' },
      });
    });
  });

  describe('desfavoritar', () => {
    it('removes the favorite scoped to the user', async () => {
      const prisma = buildPrismaMock();
      prisma.cardFavorito.deleteMany.mockResolvedValue({ count: 1 });
      const service = new GroundingCardsService(prisma as any);

      await service.desfavoritar('u1', 'c1');

      expect(prisma.cardFavorito.deleteMany).toHaveBeenCalledWith({ where: { userId: 'u1', cardId: 'c1' } });
    });
  });

  describe('adminList', () => {
    it('returns all cards including inactive ones, ordered by title', async () => {
      const prisma = buildPrismaMock();
      prisma.groundingCard.findMany.mockResolvedValue([]);
      const service = new GroundingCardsService(prisma as any);

      await service.adminList();

      expect(prisma.groundingCard.findMany).toHaveBeenCalledWith({ orderBy: { titulo: 'asc' } });
    });
  });

  describe('create', () => {
    it('creates an active card from the given data', async () => {
      const prisma = buildPrismaMock();
      prisma.groundingCard.create.mockResolvedValue(buildCard());
      const service = new GroundingCardsService(prisma as any);
      const dto = { titulo: 'Respiração 4-7-8', categoria: 'RESPIRACAO', conteudo: 'Inspire...' };

      await service.create(dto as any);

      expect(prisma.groundingCard.create).toHaveBeenCalledWith({ data: { ...dto, ativo: true } });
    });
  });

  describe('update', () => {
    it('updates a card by id with the given data', async () => {
      const prisma = buildPrismaMock();
      prisma.groundingCard.update.mockResolvedValue(buildCard());
      const service = new GroundingCardsService(prisma as any);
      const dto = { titulo: 'Novo título', categoria: 'MOVIMENTO', conteudo: 'Novo conteúdo' };

      await service.update('c1', dto as any);

      expect(prisma.groundingCard.update).toHaveBeenCalledWith({ where: { id: 'c1' }, data: dto });
    });

    it('can reactivate a card by including ativo: true in the dto', async () => {
      const prisma = buildPrismaMock();
      prisma.groundingCard.update.mockResolvedValue(buildCard({ ativo: true }));
      const service = new GroundingCardsService(prisma as any);
      const dto = { titulo: 'Título', categoria: 'RESPIRACAO', conteudo: 'Conteúdo', ativo: true };

      await service.update('c1', dto as any);

      expect(prisma.groundingCard.update).toHaveBeenCalledWith({ where: { id: 'c1' }, data: dto });
    });
  });

  describe('deactivate', () => {
    it('soft-deletes by setting ativo to false', async () => {
      const prisma = buildPrismaMock();
      prisma.groundingCard.update.mockResolvedValue(buildCard({ ativo: false }));
      const service = new GroundingCardsService(prisma as any);

      await service.deactivate('c1');

      expect(prisma.groundingCard.update).toHaveBeenCalledWith({ where: { id: 'c1' }, data: { ativo: false } });
    });
  });
});
