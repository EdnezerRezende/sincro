import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateContaDto } from './dto/create-conta.dto';
import { UpdateContaDto } from './dto/update-conta.dto';

@Injectable()
export class ContasService {
  constructor(private readonly prisma: PrismaService) {}

  list(userId: string) {
    return this.prisma.contaFinanceira.findMany({
      where: { userId },
      orderBy: { criadoEm: 'asc' },
    });
  }

  create(userId: string, dto: CreateContaDto) {
    return this.prisma.contaFinanceira.create({
      data: { userId, nome: dto.nome, tipo: dto.tipo, saldoAtual: dto.saldoAtual, cor: dto.cor },
    });
  }

  async update(userId: string, id: string, dto: UpdateContaDto) {
    await this.getOwnedOrThrow(userId, id);
    return this.prisma.contaFinanceira.update({ where: { id }, data: dto });
  }

  async remove(userId: string, id: string): Promise<void> {
    await this.getOwnedOrThrow(userId, id);
    const vinculados = await this.prisma.lancamentoFinanceiro.count({ where: { contaId: id } });
    if (vinculados > 0) {
      throw new ConflictException('Conta possui lançamentos vinculados e não pode ser excluída');
    }
    await this.prisma.contaFinanceira.delete({ where: { id } });
  }

  private async getOwnedOrThrow(userId: string, id: string) {
    const conta = await this.prisma.contaFinanceira.findFirst({ where: { id, userId } });
    if (!conta) throw new NotFoundException('Conta não encontrada');
    return conta;
  }
}
