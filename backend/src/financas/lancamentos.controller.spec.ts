import { LancamentosController } from './lancamentos.controller';

describe('LancamentosController', () => {
  it('passes query filters through to the service after resolving userId', async () => {
    const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'user-1' }) };
    const lancamentosService = { list: jest.fn().mockResolvedValue([]) };
    const controller = new LancamentosController(lancamentosService as any, usersService as any);

    await controller.list('firebase-uid-1', 'PENDENTE_REVISAO', '2026-09');

    expect(lancamentosService.list).toHaveBeenCalledWith('user-1', { status: 'PENDENTE_REVISAO', mes: '2026-09' });
  });

  it('routes PATCH .../confirmar to the service', async () => {
    const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'user-1' }) };
    const lancamentosService = { confirmar: jest.fn().mockResolvedValue({}) };
    const controller = new LancamentosController(lancamentosService as any, usersService as any);

    await controller.confirmar('firebase-uid-1', 'lanc-1', { valor: 100 });

    expect(lancamentosService.confirmar).toHaveBeenCalledWith('user-1', 'lanc-1', { valor: 100 });
  });
});
