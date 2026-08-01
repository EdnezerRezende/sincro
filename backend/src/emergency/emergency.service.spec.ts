import { NotFoundException } from '@nestjs/common';
import { EmergencyService } from './emergency.service';

describe('EmergencyService', () => {
  it('throws NotFoundException when the contact does not belong to the resolved user', async () => {
    const prisma = { trustedContact: { findFirst: jest.fn().mockResolvedValue(null) } };
    const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1' }) };
    const service = new EmergencyService(prisma as any, usersService as any);

    await expect(service.buildMessage('fb1', 'c1')).rejects.toThrow(NotFoundException);
    expect(prisma.trustedContact.findFirst).toHaveBeenCalledWith({
      where: { id: 'c1', userId: 'u1' },
    });
  });

  it('builds a neutral pre-filled wa.me message using the contact first name', async () => {
    const prisma = {
      trustedContact: {
        findFirst: jest.fn().mockResolvedValue({
          id: 'c1',
          nome: 'Marina Souza',
          whatsapp: '+55 11 99999-9999',
        }),
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
});
