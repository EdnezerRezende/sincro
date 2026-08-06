import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class GroundingCardsService {
  constructor(private readonly prisma: PrismaService) {}

  async list(categoria?: string) {
    return this.prisma.groundingCard.findMany({
      where: categoria ? { ativo: true, categoria } : { ativo: true },
      orderBy: { titulo: 'asc' },
    });
  }

  async listFavoritos(userId: string) {
    const favoritos = await this.prisma.cardFavorito.findMany({
      where: { userId },
      include: { card: true },
    });
    return favoritos.map((favorito) => favorito.card).filter((card) => card.ativo);
  }

  async favoritar(userId: string, cardId: string): Promise<void> {
    await this.prisma.cardFavorito.upsert({
      where: { userId_cardId: { userId, cardId } },
      update: {},
      create: { userId, cardId },
    });
  }

  async desfavoritar(userId: string, cardId: string): Promise<void> {
    await this.prisma.cardFavorito.deleteMany({ where: { userId, cardId } });
  }
}
