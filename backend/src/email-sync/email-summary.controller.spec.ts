import { ForbiddenException, NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import { EmailSummaryController } from './email-summary.controller';

/** Simulates the shape a failed Gmail API call actually has (see `gmail-error.util.ts`): a
 *  `.response.status` for the HTTP status Google's client returned. */
function erroGmail(status: number, message = 'Gmail API error') {
  return Object.assign(new Error(message), { response: { status } });
}

function buildDeps() {
  const emailSyncService = {
    list: jest.fn().mockResolvedValue([]),
    getOwned: jest.fn().mockResolvedValue({
      id: 'email-1',
      gmailMessageId: 'msg-1',
      remetente: 'Carlos <carlos@example.com>',
      assunto: 'Prazo',
    }),
    remover: jest.fn().mockResolvedValue(undefined),
  };
  const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1' }) };
  const connectionsService = {
    getConnectionOrThrow: jest.fn().mockResolvedValue({
      temEscopoEnvio: false,
      temEscopoAgenda: false,
      temEscopoModificacao: true,
    }),
    getDecryptedRefreshToken: jest.fn().mockResolvedValue('rt-123'),
  };
  const gmailApiClient = {
    fetchFullBody: jest.fn().mockResolvedValue({ texto: 'Corpo completo do e-mail.', ehPreview: false }),
    arquivar: jest.fn().mockResolvedValue(undefined),
    excluir: jest.fn().mockResolvedValue(undefined),
  };
  return { emailSyncService, usersService, connectionsService, gmailApiClient };
}

function buildController(deps: ReturnType<typeof buildDeps>) {
  return new EmailSummaryController(
    deps.emailSyncService as never,
    deps.usersService as never,
    deps.connectionsService as never,
    deps.gmailApiClient as never,
  );
}

describe('EmailSummaryController — conteúdo do e-mail (sem LLM)', () => {
  it('devolve o corpo completo buscado no Gmail, sem depender de nenhuma chamada a IA', async () => {
    const deps = buildDeps();
    const controller = buildController(deps);

    const result = await controller.conteudo('fb1', 'email-1');

    expect(result).toEqual({ corpo: 'Corpo completo do e-mail.', ehPreview: false });
    expect(deps.gmailApiClient.fetchFullBody).toHaveBeenCalledWith('rt-123', 'msg-1');
  });

  it('exige apenas uma conexão Gmail existente — não exige escopo de envio nem de agenda', async () => {
    const deps = buildDeps();
    const controller = buildController(deps);

    await controller.conteudo('fb1', 'email-1');

    expect(deps.connectionsService.getConnectionOrThrow).toHaveBeenCalledWith('u1');
  });

  it('token revogado/expirado (401 do Gmail) vira 403 pedindo para reconectar — nunca um 500 cru', async () => {
    const deps = buildDeps();
    deps.gmailApiClient.fetchFullBody.mockRejectedValue(erroGmail(401));
    const controller = buildController(deps);

    await expect(controller.conteudo('fb1', 'email-1')).rejects.toThrow(ForbiddenException);
  });

  it('permissão retirada pelo Google (403 do Gmail) também vira 403 pedindo para reconectar', async () => {
    const deps = buildDeps();
    deps.gmailApiClient.fetchFullBody.mockRejectedValue(erroGmail(403));
    const controller = buildController(deps);

    await expect(controller.conteudo('fb1', 'email-1')).rejects.toThrow(ForbiddenException);
  });

  it('mensagem já apagada direto no Gmail (404) vira 404, não um 500 cru', async () => {
    const deps = buildDeps();
    deps.gmailApiClient.fetchFullBody.mockRejectedValue(erroGmail(404));
    const controller = buildController(deps);

    await expect(controller.conteudo('fb1', 'email-1')).rejects.toThrow(NotFoundException);
  });

  it('falha genérica do Gmail (ex.: instabilidade) vira 503, não um 500 cru', async () => {
    const deps = buildDeps();
    deps.gmailApiClient.fetchFullBody.mockRejectedValue(erroGmail(500));
    const controller = buildController(deps);

    await expect(controller.conteudo('fb1', 'email-1')).rejects.toThrow(ServiceUnavailableException);
  });
});

describe('EmailSummaryController — arquivar', () => {
  it('arquiva no Gmail de verdade (removendo só o label INBOX) e remove a linha local no mesmo request', async () => {
    const deps = buildDeps();
    const controller = buildController(deps);

    const result = await controller.arquivar('fb1', 'email-1');

    expect(deps.gmailApiClient.arquivar).toHaveBeenCalledWith('rt-123', 'msg-1');
    expect(deps.emailSyncService.remover).toHaveBeenCalledWith('email-1');
    expect(result).toEqual({ arquivado: true });
  });

  it('recusa arquivar sem o escopo gmail.modify, sinalizando reconexão', async () => {
    const deps = buildDeps();
    deps.connectionsService.getConnectionOrThrow.mockResolvedValue({
      temEscopoEnvio: false,
      temEscopoAgenda: false,
      temEscopoModificacao: false,
    });
    const controller = buildController(deps);

    await expect(controller.arquivar('fb1', 'email-1')).rejects.toThrow(ForbiddenException);
    expect(deps.gmailApiClient.arquivar).not.toHaveBeenCalled();
    expect(deps.emailSyncService.remover).not.toHaveBeenCalled();
  });

  it('mensagem já apagada direto no Gmail (404): a linha local ainda é removida, não fica presa', async () => {
    const deps = buildDeps();
    deps.gmailApiClient.arquivar.mockRejectedValue(erroGmail(404));
    const controller = buildController(deps);

    const result = await controller.arquivar('fb1', 'email-1');

    expect(deps.emailSyncService.remover).toHaveBeenCalledWith('email-1');
    expect(result).toEqual({ arquivado: true });
  });

  it('token revogado (401 do Gmail) ao tentar arquivar vira 403 honesto, nunca 500 cru — e a linha local NÃO some', async () => {
    const deps = buildDeps();
    deps.gmailApiClient.arquivar.mockRejectedValue(erroGmail(401));
    const controller = buildController(deps);

    await expect(controller.arquivar('fb1', 'email-1')).rejects.toThrow(ForbiddenException);
    expect(deps.emailSyncService.remover).not.toHaveBeenCalled();
  });

  it('falha genérica do Gmail ao arquivar vira 503, nunca 500 cru — e a linha local NÃO some', async () => {
    const deps = buildDeps();
    deps.gmailApiClient.arquivar.mockRejectedValue(erroGmail(500));
    const controller = buildController(deps);

    await expect(controller.arquivar('fb1', 'email-1')).rejects.toThrow(ServiceUnavailableException);
    expect(deps.emailSyncService.remover).not.toHaveBeenCalled();
  });
});

describe('EmailSummaryController — excluir', () => {
  it('move para a lixeira do Gmail (messages.trash, reversível) e remove a linha local no mesmo request', async () => {
    const deps = buildDeps();
    const controller = buildController(deps);

    const result = await controller.excluir('fb1', 'email-1');

    expect(deps.gmailApiClient.excluir).toHaveBeenCalledWith('rt-123', 'msg-1');
    expect(deps.emailSyncService.remover).toHaveBeenCalledWith('email-1');
    expect(result).toEqual({ excluido: true });
  });

  it('recusa excluir sem o escopo gmail.modify, sinalizando reconexão', async () => {
    const deps = buildDeps();
    deps.connectionsService.getConnectionOrThrow.mockResolvedValue({
      temEscopoEnvio: false,
      temEscopoAgenda: false,
      temEscopoModificacao: false,
    });
    const controller = buildController(deps);

    await expect(controller.excluir('fb1', 'email-1')).rejects.toThrow(ForbiddenException);
    expect(deps.gmailApiClient.excluir).not.toHaveBeenCalled();
    expect(deps.emailSyncService.remover).not.toHaveBeenCalled();
  });

  it('mensagem já apagada direto no Gmail (404): a linha local ainda é removida, não fica presa', async () => {
    const deps = buildDeps();
    deps.gmailApiClient.excluir.mockRejectedValue(erroGmail(404));
    const controller = buildController(deps);

    const result = await controller.excluir('fb1', 'email-1');

    expect(deps.emailSyncService.remover).toHaveBeenCalledWith('email-1');
    expect(result).toEqual({ excluido: true });
  });

  it('token revogado (401 do Gmail) ao tentar excluir vira 403 honesto, nunca 500 cru — e a linha local NÃO some', async () => {
    const deps = buildDeps();
    deps.gmailApiClient.excluir.mockRejectedValue(erroGmail(401));
    const controller = buildController(deps);

    await expect(controller.excluir('fb1', 'email-1')).rejects.toThrow(ForbiddenException);
    expect(deps.emailSyncService.remover).not.toHaveBeenCalled();
  });

  it('falha genérica do Gmail ao excluir vira 503, nunca 500 cru — e a linha local NÃO some', async () => {
    const deps = buildDeps();
    deps.gmailApiClient.excluir.mockRejectedValue(erroGmail(500));
    const controller = buildController(deps);

    await expect(controller.excluir('fb1', 'email-1')).rejects.toThrow(ServiceUnavailableException);
    expect(deps.emailSyncService.remover).not.toHaveBeenCalled();
  });
});
