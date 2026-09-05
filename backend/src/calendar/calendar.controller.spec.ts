import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { CalendarController } from './calendar.controller';

function buildDeps(overrides?: { temEscopoAgenda?: boolean }) {
  const usersService = {
    getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1' }),
  };
  const connectionsService = {
    getConnectionOrThrow: jest.fn().mockResolvedValue({
      temEscopoAgenda: overrides?.temEscopoAgenda ?? true,
    }),
    getDecryptedRefreshToken: jest.fn().mockResolvedValue('rt-123'),
  };
  const calendarApiClient = {
    listarEventos: jest.fn().mockResolvedValue([]),
    criarEventoCompleto: jest.fn().mockResolvedValue({ id: 'ev1' }),
    atualizarEvento: jest.fn().mockResolvedValue({ id: 'ev1' }),
    deletarEvento: jest.fn().mockResolvedValue(undefined),
  };
  return { usersService, connectionsService, calendarApiClient };
}

function buildController(overrides?: { temEscopoAgenda?: boolean }) {
  const deps = buildDeps(overrides);
  const controller = new CalendarController(
    deps.usersService as never,
    deps.connectionsService as never,
    deps.calendarApiClient as never,
  );
  return { controller, ...deps };
}

const dtoValido = {
  titulo: 'Reunião',
  descricao: 'Pauta',
  dataHoraInicio: '2026-09-01T15:00:00-03:00',
  dataHoraFim: '2026-09-01T16:00:00-03:00',
};

describe('CalendarController — guarda de escopo de agenda', () => {
  it('rejeita com 403 quando a conexão não tem temEscopoAgenda', async () => {
    const { controller } = buildController({ temEscopoAgenda: false });

    await expect(controller.eventosProximos('fb1')).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('permite a rota quando temEscopoAgenda é true', async () => {
    const { controller, calendarApiClient } = buildController({
      temEscopoAgenda: true,
    });

    await controller.eventosProximos('fb1');

    expect(calendarApiClient.listarEventos).toHaveBeenCalledWith(
      'rt-123',
      expect.any(String),
      expect.any(String),
    );
  });
});

describe('CalendarController — roteamento para o client', () => {
  it('criarEvento repassa os campos do dto para criarEventoCompleto', async () => {
    const { controller, calendarApiClient } = buildController();

    await controller.criarEvento('fb1', dtoValido);

    expect(calendarApiClient.criarEventoCompleto).toHaveBeenCalledWith(
      'rt-123',
      {
        titulo: 'Reunião',
        descricao: 'Pauta',
        dataHoraInicio: '2026-09-01T15:00:00-03:00',
        dataHoraFim: '2026-09-01T16:00:00-03:00',
      },
    );
  });

  it('atualizarEvento repassa o id e os campos do dto para atualizarEvento do client', async () => {
    const { controller, calendarApiClient } = buildController();

    await controller.atualizarEvento('fb1', 'ev1', dtoValido);

    expect(calendarApiClient.atualizarEvento).toHaveBeenCalledWith(
      'rt-123',
      'ev1',
      {
        titulo: 'Reunião',
        descricao: 'Pauta',
        dataHoraInicio: '2026-09-01T15:00:00-03:00',
        dataHoraFim: '2026-09-01T16:00:00-03:00',
      },
    );
  });

  it('deletarEvento repassa o id para deletarEvento do client e confirma sucesso', async () => {
    const { controller, calendarApiClient } = buildController();

    const resultado = await controller.deletarEvento('fb1', 'ev1');

    expect(calendarApiClient.deletarEvento).toHaveBeenCalledWith(
      'rt-123',
      'ev1',
    );
    expect(resultado).toEqual({ sucesso: true });
  });
});

describe('CalendarController — validação de entrada', () => {
  it('rejeita eventosMes com ano fora da faixa razoável em vez de deixar Date.UTC/toISOString explodir', async () => {
    const { controller } = buildController();

    await expect(
      controller.eventosMes('fb1', { ano: '275760', mes: '1' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejeita eventosMes com mes fora de 1-12', async () => {
    const { controller } = buildController();

    await expect(
      controller.eventosMes('fb1', { ano: '2026', mes: '13' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('aceita eventosMes com ano/mes válidos', async () => {
    const { controller, calendarApiClient } = buildController();

    await controller.eventosMes('fb1', { ano: '2026', mes: '9' });

    expect(calendarApiClient.listarEventos).toHaveBeenCalled();
  });

  it('rejeita criarEvento quando dataHoraFim não é depois de dataHoraInicio', async () => {
    const { controller } = buildController();

    await expect(
      controller.criarEvento('fb1', {
        ...dtoValido,
        dataHoraFim: dtoValido.dataHoraInicio,
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejeita criarEvento quando dataHoraFim é antes de dataHoraInicio', async () => {
    const { controller } = buildController();

    await expect(
      controller.criarEvento('fb1', {
        ...dtoValido,
        dataHoraInicio: '2026-09-01T16:00:00-03:00',
        dataHoraFim: '2026-09-01T15:00:00-03:00',
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejeita atualizarEvento com o mesmo problema de intervalo invertido', async () => {
    const { controller } = buildController();

    await expect(
      controller.atualizarEvento('fb1', 'ev1', {
        ...dtoValido,
        dataHoraFim: dtoValido.dataHoraInicio,
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});
