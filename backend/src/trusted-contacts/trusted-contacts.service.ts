import { BadRequestException, Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { UsersService } from '../users/users.service';
import { CreateTrustedContactDto } from './dto/create-trusted-contact.dto';

@Injectable()
export class TrustedContactsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly usersService: UsersService,
  ) {}

  async create(firebaseUid: string, dto: CreateTrustedContactDto) {
    if (!dto.consentimentoAceito) {
      throw new BadRequestException('Consentimento é obrigatório para cadastrar um contato');
    }

    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);

    return this.prisma.trustedContact.create({
      data: {
        userId: user.id,
        nome: dto.nome,
        relacao: dto.relacao,
        whatsapp: dto.whatsapp,
        prioridade: dto.prioridade,
        consentimentoAceitoEm: new Date(),
      },
    });
  }

  async list(firebaseUid: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    return this.prisma.trustedContact.findMany({
      where: { userId: user.id },
      orderBy: { prioridade: 'asc' },
    });
  }

  async remove(firebaseUid: string, contactId: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    await this.prisma.trustedContact.deleteMany({
      where: { id: contactId, userId: user.id },
    });
  }
}
