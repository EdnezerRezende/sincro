import { CartoesController } from './cartoes.controller';

describe('CartoesController', () => {
  it('resolves the Prisma userId from the Firebase uid before listing', async () => {
    const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'user-1' }) };
    const cartoesService = { list: jest.fn().mockResolvedValue([]) };
    const controller = new CartoesController(cartoesService as any, usersService as any);

    await controller.list('firebase-uid-1');

    expect(usersService.getByFirebaseUidOrThrow).toHaveBeenCalledWith('firebase-uid-1');
    expect(cartoesService.list).toHaveBeenCalledWith('user-1');
  });
});
