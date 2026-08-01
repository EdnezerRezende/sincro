import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { UsersService } from '../users/users.service';

@Injectable()
export class EmergencyService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly usersService: UsersService,
  ) {}

  async buildMessage(firebaseUid: string, contactId: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const contact = await this.prisma.trustedContact.findFirst({
      where: { id: contactId, userId: user.id },
    });

    if (!contact) {
      throw new NotFoundException('Contato não encontrado');
    }

    const primeiroNome = contact.nome.split(' ')[0];
    const mensagem = `Oi ${primeiroNome}, estou passando por um momento difícil agora e queria avisar. Não precisa ligar se não for possível.`;
    const numeroLimpo = contact.whatsapp.replace(/\D/g, '');
    const waUrl = `https://wa.me/${numeroLimpo}?text=${encodeURIComponent(mensagem)}`;

    return {
      contactId: contact.id,
      contactName: contact.nome,
      whatsapp: contact.whatsapp,
      message: mensagem,
      waUrl,
    };
  }
}
