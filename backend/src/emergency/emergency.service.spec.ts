import { NotFoundException } from '@nestjs/common';
import { EmergencyService } from './emergency.service';

describe('EmergencyService', () => {
  it('throws NotFoundException when the contact does not belong to the resolved user', async () => {
    const prisma = { trustedContact: { findMany: jest.fn().mockResolvedValue([]) } };
    const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1' }) };
    const service = new EmergencyService(prisma as any, usersService as any);

    await expect(service.buildMessage('fb1', 'c1')).rejects.toThrow(NotFoundException);
    expect(prisma.trustedContact.findMany).toHaveBeenCalledWith({
      where: { id: { in: ['c1'] }, userId: 'u1' },
    });
  });

  it('builds a neutral pre-filled wa.me message using the contact first name', async () => {
    const prisma = {
      trustedContact: {
        findMany: jest.fn().mockResolvedValue([{
          id: 'c1',
          nome: 'Marina Souza',
          whatsapp: '+55 11 99999-9999',
        }]),
      },
    };
    const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1' }) };
    const service = new EmergencyService(prisma as any, usersService as any);

    const result = await service.buildMessage('fb1', 'c1');

    expect(result.contactId).toBe('c1');
    expect(result.contactName).toBe('Marina Souza');
    expect(result.message).toBe(
      'Oi Marina, estou passando por um momento difícil agora e queria avisar. Não precisa ligar se não for possível.',
    );
    expect(result.waUrl).toBe(
      `https://wa.me/5511999999999?text=${encodeURIComponent(result.message)}`,
    );
  });

  describe('buildMessages', () => {
    const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1' }) };
    const contatos = [
      { id: 'c1', nome: 'Marina Souza', whatsapp: '+55 11 99999-9999' },
      { id: 'c2', nome: 'João Pedro Lima', whatsapp: '+5511988880000' },
    ];

    it('returns one message per contact, in the requested order, with the default template', async () => {
      const prisma = { trustedContact: { findMany: jest.fn().mockResolvedValue([contatos[1], contatos[0]]) } };
      const service = new EmergencyService(prisma as any, usersService as any);

      const result = await service.buildMessages('fb1', ['c1', 'c2']);

      expect(prisma.trustedContact.findMany).toHaveBeenCalledWith({
        where: { id: { in: ['c1', 'c2'] }, userId: 'u1' },
      });
      expect(result.map((m) => m.contactId)).toEqual(['c1', 'c2']);
      expect(result[0].message).toBe(
        'Oi Marina, estou passando por um momento difícil agora e queria avisar. Não precisa ligar se não for possível.',
      );
      expect(result[1].message.startsWith('Oi João,')).toBe(true);
      expect(result[1].waUrl).toBe(`https://wa.me/5511988880000?text=${encodeURIComponent(result[1].message)}`);
    });

    it('applies a custom template replacing {primeiro nome} for each contact', async () => {
      const prisma = { trustedContact: { findMany: jest.fn().mockResolvedValue(contatos) } };
      const service = new EmergencyService(prisma as any, usersService as any);

      const result = await service.buildMessages('fb1', ['c1', 'c2'], 'Oi {primeiro nome}, pode me ligar?');

      expect(result[0].message).toBe('Oi Marina, pode me ligar?');
      expect(result[1].message).toBe('Oi João, pode me ligar?');
    });

    it('keeps a template without the placeholder as-is', async () => {
      const prisma = { trustedContact: { findMany: jest.fn().mockResolvedValue([contatos[0]]) } };
      const service = new EmergencyService(prisma as any, usersService as any);

      const result = await service.buildMessages('fb1', ['c1'], 'Preciso de ajuda agora.');

      expect(result[0].message).toBe('Preciso de ajuda agora.');
    });

    it('throws NotFoundException when any contact is missing or belongs to another user', async () => {
      const prisma = { trustedContact: { findMany: jest.fn().mockResolvedValue([contatos[0]]) } };
      const service = new EmergencyService(prisma as any, usersService as any);

      await expect(service.buildMessages('fb1', ['c1', 'c2'])).rejects.toThrow(NotFoundException);
    });
  });
});
