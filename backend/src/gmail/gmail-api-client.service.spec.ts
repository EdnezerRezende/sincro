import { GmailApiClient } from './gmail-api-client.service';

jest.mock('googleapis', () => {
  const get = jest.fn();
  const send = jest.fn().mockResolvedValue({ data: {} });
  return {
    google: { gmail: jest.fn(() => ({ users: { messages: { get, send } } })) },
    __get: get,
    __send: send,
  };
});

function mocks() {
  return jest.requireMock('googleapis') as {
    __get: jest.Mock;
    __send: jest.Mock;
  };
}

function buildClient() {
  const oauthService = { authenticatedClientFor: jest.fn(() => ({ fake: 'auth' })) };
  return new GmailApiClient(oauthService as never);
}

/** Reconstrói a mensagem que foi realmente entregue ao Gmail. */
function mensagemEnviada() {
  const { __send } = mocks();
  const requestBody = __send.mock.calls[0][0].requestBody;
  const raw = Buffer.from(requestBody.raw, 'base64url').toString('utf8');
  const separador = raw.indexOf('\r\n\r\n');
  const blocoCabecalhos = raw.slice(0, separador);
  const corpo = raw.slice(separador + 4);
  // Linhas iniciadas por espaço/tab são continuações (folding), não cabeçalhos novos.
  const linhasDeCabecalho = blocoCabecalhos.split(/\r\n(?![ \t])/);
  const cabecalho = (nome: string) => {
    const linha = linhasDeCabecalho.find((l) => l.toLowerCase().startsWith(`${nome.toLowerCase()}:`));
    return linha === undefined ? undefined : linha.slice(nome.length + 1).trim();
  };
  return { raw, corpo, linhasDeCabecalho, cabecalho, threadId: requestBody.threadId };
}

/** Desfaz o encoded-word RFC 2047 (`=?UTF-8?B?...?=`), inclusive quando dobrado em várias partes. */
function decodificarRfc2047(valor: string): string {
  const palavras = [...valor.matchAll(/=\?UTF-8\?B\?([^?]*)\?=/g)];
  if (palavras.length === 0) return valor;
  return Buffer.concat(palavras.map((p) => Buffer.from(p[1], 'base64'))).toString('utf8');
}

describe('GmailApiClient.sendReply', () => {
  beforeEach(() => {
    const { __get, __send } = mocks();
    __get.mockReset();
    __send.mockReset();
    __send.mockResolvedValue({ data: {} });
    __get.mockResolvedValue({
      data: {
        threadId: 'thread-123',
        payload: {
          headers: [
            { name: 'Message-Id', value: '<msg-original@example.com>' },
            { name: 'References', value: '<msg-anterior@example.com>' },
          ],
        },
      },
    });
  });

  it('envia o texto do usuário byte a byte, sem nenhuma alteração', async () => {
    const texto = 'Olá, Carlos!\r\n\r\nEnvio o relatório até sexta às 15h.\r\n\r\nAbraço,\nAna — 100% ok.';

    await buildClient().sendReply('rt-123', {
      gmailMessageId: 'msg-1',
      para: 'Carlos <carlos@example.com>',
      assunto: 'Prazo do relatorio',
      texto,
    });

    expect(mensagemEnviada().corpo).toBe(texto);
  });

  it('encadeia a resposta na thread original (In-Reply-To, References e threadId)', async () => {
    await buildClient().sendReply('rt-123', {
      gmailMessageId: 'msg-1',
      para: 'Carlos <carlos@example.com>',
      assunto: 'Prazo do relatorio',
      texto: 'Ok!',
    });

    const enviada = mensagemEnviada();
    expect(enviada.threadId).toBe('thread-123');
    expect(enviada.cabecalho('In-Reply-To')).toBe('<msg-original@example.com>');
    expect(enviada.cabecalho('References')).toBe(
      '<msg-anterior@example.com> <msg-original@example.com>',
    );
    expect(enviada.cabecalho('To')).toBe('Carlos <carlos@example.com>');
    expect(enviada.cabecalho('Subject')).toBe('Re: Prazo do relatorio');
    expect(mocks().__get).toHaveBeenCalledWith(
      expect.objectContaining({ userId: 'me', id: 'msg-1' }),
    );
  });

  it('não deixa um CRLF no assunto injetar cabeçalhos extras na mensagem', async () => {
    await buildClient().sendReply('rt-123', {
      gmailMessageId: 'msg-1',
      para: 'Carlos <carlos@example.com>',
      assunto: 'Prazo\r\nBcc: atacante@evil.com',
      texto: 'Ok!',
    });

    const enviada = mensagemEnviada();
    expect(enviada.cabecalho('Bcc')).toBeUndefined();
    expect(enviada.cabecalho('Subject')).toBe('Re: Prazo Bcc: atacante@evil.com');
    expect(enviada.linhasDeCabecalho).toEqual([
      'MIME-Version: 1.0',
      'To: Carlos <carlos@example.com>',
      'Subject: Re: Prazo Bcc: atacante@evil.com',
      'In-Reply-To: <msg-original@example.com>',
      'References: <msg-anterior@example.com> <msg-original@example.com>',
      'Content-Type: text/plain; charset="UTF-8"',
    ]);
  });

  it('não deixa um CRLF no destinatário injetar cabeçalhos extras na mensagem', async () => {
    await buildClient().sendReply('rt-123', {
      gmailMessageId: 'msg-1',
      para: 'Carlos <carlos@example.com>\r\nBcc: atacante@evil.com',
      assunto: 'Prazo',
      texto: 'Ok!',
    });

    const enviada = mensagemEnviada();
    expect(enviada.cabecalho('Bcc')).toBeUndefined();
    expect(enviada.linhasDeCabecalho).toHaveLength(6);
    expect(enviada.cabecalho('To')).toBe('Carlos <carlos@example.com> Bcc: atacante@evil.com');
  });

  it('não deixa um CRLF vindo dos cabeçalhos do e-mail original injetar cabeçalhos extras', async () => {
    mocks().__get.mockResolvedValue({
      data: {
        threadId: 'thread-123',
        payload: {
          headers: [{ name: 'Message-Id', value: '<msg@example.com>\r\nBcc: atacante@evil.com' }],
        },
      },
    });

    await buildClient().sendReply('rt-123', {
      gmailMessageId: 'msg-1',
      para: 'Carlos <carlos@example.com>',
      assunto: 'Prazo',
      texto: 'Ok!',
    });

    const enviada = mensagemEnviada();
    expect(enviada.cabecalho('Bcc')).toBeUndefined();
    expect(enviada.linhasDeCabecalho).toHaveLength(6);
  });

  it('codifica um assunto acentuado em RFC 2047, que volta idêntico ao ser decodificado', async () => {
    await buildClient().sendReply('rt-123', {
      gmailMessageId: 'msg-1',
      para: 'Carlos <carlos@example.com>',
      assunto: 'Confirmação da reunião de segunda',
      texto: 'Ok!',
    });

    const assunto = mensagemEnviada().cabecalho('Subject') as string;
    expect(assunto).toMatch(/^=\?UTF-8\?B\?/);
    expect(decodificarRfc2047(assunto)).toBe('Re: Confirmação da reunião de segunda');
  });

  it('quebra um assunto acentuado longo em encoded-words curtos sem corromper os acentos', async () => {
    const assuntoLongo =
      'Confirmação da reunião de alinhamento sobre a revisão do orçamento anual e das ações prioritárias';

    await buildClient().sendReply('rt-123', {
      gmailMessageId: 'msg-1',
      para: 'Carlos <carlos@example.com>',
      assunto: assuntoLongo,
      texto: 'Ok!',
    });

    const enviada = mensagemEnviada();
    const assunto = enviada.cabecalho('Subject') as string;
    for (const parte of assunto.split(/\r\n[ \t]+/)) {
      expect(parte.length).toBeLessThanOrEqual(75);
    }
    expect(decodificarRfc2047(assunto)).toBe(`Re: ${assuntoLongo}`);
    // A dobra gera linhas de continuação, nunca cabeçalhos novos.
    expect(enviada.linhasDeCabecalho).toHaveLength(6);
  });
});
