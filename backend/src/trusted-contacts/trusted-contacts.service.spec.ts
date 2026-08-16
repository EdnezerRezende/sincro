import { BadRequestException } from '@nestjs/common';
import { TrustedContactsService } from './trusted-contacts.service';
import { CreateTrustedContactDto } from './dto/create-trusted-contact.dto';

function buildDto(overrides: Partial<CreateTrustedContactDto> = {}): CreateTrustedContactDto {
  return {
    nome: 'Dra. Marina',
    relacao: 'PSICOLOGO',
    whatsapp: '+5511999999999',
    prioridade: 0,
    consentimentoAceito: true,
    ...overrides,
  };
}

describe('TrustedContactsService', () => {
  it('rejects creation without consent', async () => {
    const prisma = { trustedContact: { create: jest.fn() } };
    const usersService = { getByFirebaseUidOrThrow: jest.fn() };
    const service = new TrustedContactsService(prisma as any, usersService as any);

    await expect(
      service.create('fb1', buildDto({ consentimentoAceito: false })),
    ).rejects.toThrow(BadRequestException);
    expect(prisma.trustedContact.create).not.toHaveBeenCalled();
  });

  it('creates a contact scoped to the resolved user id with a consent timestamp', async () => {
    const prisma = { trustedContact: { create: jest.fn().mockResolvedValue({ id: 'c1' }) } };
    const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1' }) };
    const service = new TrustedContactsService(prisma as any, usersService as any);

    await service.create('fb1', buildDto());

    expect(prisma.trustedContact.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        userId: 'u1',
        nome: 'Dra. Marina',
        relacao: 'PSICOLOGO',
        whatsapp: '+5511999999999',
        prioridade: 0,
        consentimentoAceitoEm: expect.any(Date),
      }),
    });
  });

  it('lists contacts ordered by prioridade, scoped to the resolved user id', async () => {
    const prisma = { trustedContact: { findMany: jest.fn().mockResolvedValue([]) } };
    const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1' }) };
    const service = new TrustedContactsService(prisma as any, usersService as any);

    await service.list('fb1');

    expect(prisma.trustedContact.findMany).toHaveBeenCalledWith({
      where: { userId: 'u1' },
      orderBy: { prioridade: 'asc' },
    });
  });

  it('removes a contact only if it belongs to the resolved user id', async () => {
    const prisma = { trustedContact: { deleteMany: jest.fn().mockResolvedValue({ count: 1 }) } };
    const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1' }) };
    const service = new TrustedContactsService(prisma as any, usersService as any);

    await service.remove('fb1', 'c1');

    expect(prisma.trustedContact.deleteMany).toHaveBeenCalledWith({
      where: { id: 'c1', userId: 'u1' },
    });
  });
});
