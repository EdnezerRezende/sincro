import { GroundingCardsController } from './grounding-cards.controller';

describe('GroundingCardsController', () => {
  it('passes the categoria query param through to the service', async () => {
    const service = { list: jest.fn().mockResolvedValue([]) };
    const usersService = { getByFirebaseUidOrThrow: jest.fn() };
    const controller = new GroundingCardsController(service as any, usersService as any);

    await controller.list('RESPIRACAO');

    expect(service.list).toHaveBeenCalledWith('RESPIRACAO');
  });

  it('omits categoria when the query param is absent', async () => {
    const service = { list: jest.fn().mockResolvedValue([]) };
    const usersService = { getByFirebaseUidOrThrow: jest.fn() };
    const controller = new GroundingCardsController(service as any, usersService as any);

    await controller.list(undefined);

    expect(service.list).toHaveBeenCalledWith(undefined);
  });

  it('lists favoritos scoped to the resolved user id, not a client-supplied one', async () => {
    const service = { listFavoritos: jest.fn().mockResolvedValue([]) };
    const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1' }) };
    const controller = new GroundingCardsController(service as any, usersService as any);

    await controller.listFavoritos('fb1');

    expect(usersService.getByFirebaseUidOrThrow).toHaveBeenCalledWith('fb1');
    expect(service.listFavoritos).toHaveBeenCalledWith('u1');
  });

  it('favoritar resolves the user id before calling the service', async () => {
    const service = { favoritar: jest.fn().mockResolvedValue(undefined) };
    const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1' }) };
    const controller = new GroundingCardsController(service as any, usersService as any);

    await controller.favoritar('fb1', 'c1');

    expect(service.favoritar).toHaveBeenCalledWith('u1', 'c1');
  });

  it('desfavoritar resolves the user id before calling the service', async () => {
    const service = { desfavoritar: jest.fn().mockResolvedValue(undefined) };
    const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1' }) };
    const controller = new GroundingCardsController(service as any, usersService as any);

    await controller.desfavoritar('fb1', 'c1');

    expect(service.desfavoritar).toHaveBeenCalledWith('u1', 'c1');
  });
});
