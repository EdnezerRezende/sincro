import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { UsersService } from '../users/users.service';

export const EMERGENCY_NAME_PLACEHOLDER = '{primeiro nome}';
export const DEFAULT_EMERGENCY_TEMPLATE =
  `Oi ${EMERGENCY_NAME_PLACEHOLDER}, estou passando por um momento difícil agora e queria avisar. Não precisa ligar se não for possível.`;

export interface EmergencyMessage {
  contactId: string;
  contactName: string;
  whatsapp: string;
  message: string;
  waUrl: string;
}

@Injectable()
export class EmergencyService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly usersService: UsersService,
  ) {}

  /** Mantido por compatibilidade com clientes antigos (`POST /emergency/message`). */
  async buildMessage(firebaseUid: string, contactId: string): Promise<EmergencyMessage> {
    const [message] = await this.buildMessages(firebaseUid, [contactId]);
    return message;
  }

  async buildMessages(firebaseUid: string, contactIds: string[], template?: string): Promise<EmergencyMessage[]> {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const contacts = await this.prisma.trustedContact.findMany({
      where: { id: { in: contactIds }, userId: user.id },
    });
    const byId = new Map(contacts.map((contact) => [contact.id, contact]));
    const missing = contactIds.filter((id) => !byId.has(id));
    if (missing.length > 0) {
      throw new NotFoundException('Contato não encontrado');
    }

    const effectiveTemplate = template?.trim() ? template : DEFAULT_EMERGENCY_TEMPLATE;
    return contactIds.map((id) => {
      const contact = byId.get(id)!;
      const primeiroNome = contact.nome.split(' ')[0];
      const mensagem = effectiveTemplate.split(EMERGENCY_NAME_PLACEHOLDER).join(primeiroNome);
      const numeroLimpo = contact.whatsapp.replace(/\D/g, '');
      return {
        contactId: contact.id,
        contactName: contact.nome,
        whatsapp: contact.whatsapp,
        message: mensagem,
        waUrl: `https://wa.me/${numeroLimpo}?text=${encodeURIComponent(mensagem)}`,
      };
    });
  }
}
