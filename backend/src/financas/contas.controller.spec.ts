import { ContasController } from './contas.controller';

describe('ContasController', () => {
  it('resolves the Prisma userId from the Firebase uid before listing', async () => {
    const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'user-1' }) };
    const contasService = { list: jest.fn().mockResolvedValue([]) };
    const controller = new ContasController(contasService as any, usersService as any);

    await controller.list('firebase-uid-1');

    expect(usersService.getByFirebaseUidOrThrow).toHaveBeenCalledWith('firebase-uid-1');
    expect(contasService.list).toHaveBeenCalledWith('user-1');
  });
});
