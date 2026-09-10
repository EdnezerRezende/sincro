import { ForbiddenException, ServiceUnavailableException } from '@nestjs/common';
import { EmailReplyController } from './email-reply.controller';

function buildDeps() {
  const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1' }) };
  const emailSyncService = {
    getOwned: jest.fn().mockResolvedValue({
      id: 'email-1',
      gmailMessageId: 'msg-1',
      remetente: 'Carlos <carlos@example.com>',
      assunto: 'Prazo',
    }),
  };
  const connectionsService = {
    getConnectionOrThrow: jest
      .fn()
      .mockResolvedValue({ temEscopoEnvio: true, temEscopoAgenda: true, temEscopoModificacao: true }),
    getDecryptedRefreshToken: jest.fn().mockResolvedValue('rt-123'),
  };
  const gmailApiClient = {
    fetchFullBody: jest.fn().mockResolvedValue({ texto: 'Qual o prazo da entrega?', ehPreview: false }),
    sendReply: jest.fn().mockResolvedValue(undefined),
  };
  const calendarApiClient = { criarEvento: jest.fn() };
  const draftService = { gerar: jest.fn() };
  const extractionService = { extrair: jest.fn() };
  return {
    usersService,
    emailSyncService,
    connectionsService,
    gmailApiClient,
    calendarApiClient,
    draftService,
    extractionService,
  };
}

function buildController(deps: ReturnType<typeof buildDeps>) {
  return new EmailReplyController(
    deps.usersService as never,
    deps.emailSyncService as never,
    deps.connectionsService as never,
    deps.gmailApiClient as never,
    deps.calendarApiClient as never,
    deps.draftService as never,
    deps.extractionService as never,
  );
}

describe('EmailReplyController — geração de rascunhos', () => {
  it('devolve os rascunhos quando o serviço de IA responde com sucesso', async () => {
    const deps = buildDeps();
    deps.draftService.gerar.mockResolvedValue({ direto: 'a', formal: 'b', padrao: 'c' });
    const controller = buildController(deps);

    const result = await controller.gerarRascunhos('fb1', 'email-1');

    expect(result).toEqual({ direto: 'a', formal: 'b', padrao: 'c' });
  });

  it('converte uma falha do serviço de IA (ex.: conta Anthropic sem créditos) em 503, nunca 500', async () => {
    const deps = buildDeps();
    deps.draftService.gerar.mockRejectedValue(
      Object.assign(new Error('400 {"type":"error","error":{"type":"invalid_request_error"}}'), {
        status: 400,
      }),
    );
    const controller = buildController(deps);

    await expect(controller.gerarRascunhos('fb1', 'email-1')).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
  });

  it('converte um token do Gmail revogado (fetchFullBody) em 403 honesto, nunca 500 — nunca chama a IA', async () => {
    const deps = buildDeps();
    deps.gmailApiClient.fetchFullBody.mockRejectedValue(Object.assign(new Error('invalid_grant'), { status: 401 }));
    const controller = buildController(deps);

    await expect(controller.gerarRascunhos('fb1', 'email-1')).rejects.toBeInstanceOf(ForbiddenException);
    expect(deps.draftService.gerar).not.toHaveBeenCalled();
  });
});

describe('EmailReplyController — envio de resposta', () => {
  it('converte um token do Gmail revogado (sendReply) em 403 honesto, nunca 500', async () => {
    const deps = buildDeps();
    deps.gmailApiClient.sendReply.mockRejectedValue(Object.assign(new Error('invalid_grant'), { status: 403 }));
    const controller = buildController(deps);

    await expect(
      controller.enviar('fb1', 'email-1', { texto: 'Combinado, até sexta.' } as never),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('converte uma falha genérica do Gmail (sendReply) em 503, nunca 500', async () => {
    const deps = buildDeps();
    deps.gmailApiClient.sendReply.mockRejectedValue(Object.assign(new Error('boom'), { status: 500 }));
    const controller = buildController(deps);

    await expect(
      controller.enviar('fb1', 'email-1', { texto: 'Combinado, até sexta.' } as never),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
  });

  it('envia normalmente e nunca deixa uma falha (que não aconteceu) na extração de compromisso derrubar a resposta', async () => {
    const deps = buildDeps();
    deps.extractionService.extrair.mockResolvedValue(null);
    const controller = buildController(deps);

    const result = await controller.enviar('fb1', 'email-1', { texto: 'Combinado, até sexta.' } as never);

    expect(result).toEqual({ enviado: true, compromissoSugerido: null });
  });
});

describe('EmailReplyController — confirmação de compromisso na agenda', () => {
  const dto = { tituloCompromisso: 'Ligar para o cliente', dataHoraLimite: '2026-09-10T10:00:00-03:00', antecedenciaMinutos: 60 };

  it('converte um token do Gmail/Google revogado (criarEvento) em 403 honesto, nunca 500', async () => {
    const deps = buildDeps();
    deps.calendarApiClient.criarEvento.mockRejectedValue(Object.assign(new Error('invalid_grant'), { status: 401 }));
    const controller = buildController(deps);

    await expect(controller.confirmarCompromisso('fb1', dto as never)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('converte uma falha genérica do Google Agenda (criarEvento) em 503, nunca 500', async () => {
    const deps = buildDeps();
    deps.calendarApiClient.criarEvento.mockRejectedValue(Object.assign(new Error('boom'), { status: 500 }));
    const controller = buildController(deps);

    await expect(controller.confirmarCompromisso('fb1', dto as never)).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
  });

  it('agenda normalmente quando o Google Agenda responde com sucesso', async () => {
    const deps = buildDeps();
    deps.calendarApiClient.criarEvento.mockResolvedValue(undefined);
    const controller = buildController(deps);

    const result = await controller.confirmarCompromisso('fb1', dto as never);

    expect(result).toEqual({ agendado: true });
  });
});
