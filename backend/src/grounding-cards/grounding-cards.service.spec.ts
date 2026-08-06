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
});
