import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateGroundingCardDto } from './dto/create-grounding-card.dto';
import { UpdateGroundingCardDto } from './dto/update-grounding-card.dto';

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
      orderBy: { card: { titulo: 'asc' } },
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

  async adminList() {
    return this.prisma.groundingCard.findMany({ orderBy: { titulo: 'asc' } });
  }

  async create(dto: CreateGroundingCardDto) {
    return this.prisma.groundingCard.create({ data: { ...dto, ativo: true } });
  }

  async update(id: string, dto: UpdateGroundingCardDto) {
    return this.prisma.groundingCard.update({ where: { id }, data: dto });
  }

  async deactivate(id: string): Promise<void> {
    await this.prisma.groundingCard.update({ where: { id }, data: { ativo: false } });
  }
}
