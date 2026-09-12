import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateCartaoDto } from './dto/create-cartao.dto';
import { UpdateCartaoDto } from './dto/update-cartao.dto';

@Injectable()
export class CartoesService {
  constructor(private readonly prisma: PrismaService) {}

  list(userId: string) {
    return this.prisma.cartaoCredito.findMany({
      where: { userId },
      orderBy: { criadoEm: 'asc' },
    });
  }

  create(userId: string, dto: CreateCartaoDto) {
    return this.prisma.cartaoCredito.create({
      data: {
        userId,
        nome: dto.nome,
        diaFechamento: dto.diaFechamento,
        diaVencimento: dto.diaVencimento,
        limiteTotal: dto.limiteTotal,
        cor: dto.cor,
      },
    });
  }

  async update(userId: string, id: string, dto: UpdateCartaoDto) {
    await this.getOwnedOrThrow(userId, id);
    return this.prisma.cartaoCredito.update({ where: { id }, data: dto });
  }

  async remove(userId: string, id: string): Promise<void> {
    await this.getOwnedOrThrow(userId, id);
    const vinculados = await this.prisma.lancamentoFinanceiro.count({ where: { cartaoId: id, userId } });
    if (vinculados > 0) {
      throw new ConflictException('Cartão possui lançamentos vinculados e não pode ser excluído');
    }
    await this.prisma.cartaoCredito.delete({ where: { id } });
  }

  private async getOwnedOrThrow(userId: string, id: string) {
    const cartao = await this.prisma.cartaoCredito.findFirst({ where: { id, userId } });
    if (!cartao) throw new NotFoundException('Cartão não encontrado');
    return cartao;
  }
}
