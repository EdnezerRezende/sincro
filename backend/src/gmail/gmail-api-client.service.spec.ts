import { Logger } from '@nestjs/common';
import { PDFParse } from 'pdf-parse';
import { GmailApiClient } from './gmail-api-client.service';

jest.mock('googleapis', () => {
  const get = jest.fn();
  const send = jest.fn().mockResolvedValue({ data: {} });
  const list = jest.fn().mockResolvedValue({ data: { messages: [] } });
  const modify = jest.fn().mockResolvedValue({ data: {} });
  const trash = jest.fn().mockResolvedValue({ data: {} });
  const getProfile = jest.fn().mockResolvedValue({ data: { historyId: 'h1' } });
  const historyList = jest.fn().mockResolvedValue({ data: { history: [] } });
  const attachmentsGet = jest.fn();
  const labelsList = jest.fn().mockResolvedValue({ data: { labels: [] } });
  return {
    google: {
      gmail: jest.fn(() => ({
        users: {
          messages: {
            get,
            send,
            list,
            modify,
            trash,
            attachments: { get: attachmentsGet },
          },
          getProfile,
          history: { list: historyList },
          labels: { list: labelsList },
        },
      })),
    },
    __get: get,
    __send: send,
    __list: list,
    __modify: modify,
    __trash: trash,
    __getProfile: getProfile,
    __historyList: historyList,
    __attachmentsGet: attachmentsGet,
    __labelsList: labelsList,
  };
});

function mocks() {
  return jest.requireMock('googleapis');
}

function buildClient() {
  const oauthService = {
    authenticatedClientFor: jest.fn(() => ({ fake: 'auth' })),
  };
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
    const linha = linhasDeCabecalho.find((l) =>
      l.toLowerCase().startsWith(`${nome.toLowerCase()}:`),
    );
    return linha === undefined
      ? undefined
      : linha.slice(nome.length + 1).trim();
  };
  return {
    raw,
    corpo,
    linhasDeCabecalho,
    cabecalho,
    threadId: requestBody.threadId,
  };
}

/** Desfaz o encoded-word RFC 2047 (`=?UTF-8?B?...?=`), inclusive quando dobrado em várias partes. */
function decodificarRfc2047(valor: string): string {
  const palavras = [...valor.matchAll(/=\?UTF-8\?B\?([^?]*)\?=/g)];
  if (palavras.length === 0) return valor;
  return Buffer.concat(
    palavras.map((p) => Buffer.from(p[1], 'base64')),
  ).toString('utf8');
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
    const texto =
      'Olá, Carlos!\r\n\r\nEnvio o relatório até sexta às 15h.\r\n\r\nAbraço,\nAna — 100% ok.';

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
    expect(enviada.cabecalho('Subject')).toBe(
      'Re: Prazo Bcc: atacante@evil.com',
    );
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
    expect(enviada.cabecalho('To')).toBe(
      'Carlos <carlos@example.com> Bcc: atacante@evil.com',
    );
  });

  it('não deixa um CRLF vindo dos cabeçalhos do e-mail original injetar cabeçalhos extras', async () => {
    mocks().__get.mockResolvedValue({
      data: {
        threadId: 'thread-123',
        payload: {
          headers: [
            {
              name: 'Message-Id',
              value: '<msg@example.com>\r\nBcc: atacante@evil.com',
            },
          ],
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
    expect(decodificarRfc2047(assunto)).toBe(
      'Re: Confirmação da reunião de segunda',
    );
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

  it('codifica o nome de exibição do destinatário em RFC 2047 sem corromper o endereço', async () => {
    await buildClient().sendReply('rt-123', {
      gmailMessageId: 'msg-1',
      para: 'João <joao@example.com>',
      assunto: 'Prazo',
      texto: 'Ok!',
    });

    const para = mensagemEnviada().cabecalho('To') as string;
    expect(para).toMatch(/^=\?UTF-8\?B\?.*\?= <joao@example\.com>$/);
    expect(decodificarRfc2047(para)).toBe('João');
  });
});

/** Encena `messages.list` devolvendo, em sequência, uma página por entrada de `paginas`
 *  (`{ ids: quantidade, nextPageToken? }`) — cada id é globalmente único (`m1`, `m2`, ...) para dar
 *  para contar quantas vezes `messages.get` foi chamado no total. `messages.get`, `getProfile` e
 *  `history.list` ficam com um fallback neutro (mensagem sempre com `INBOX`, sem ruído) — os testes
 *  de paginação não olham para dentro das mensagens, só para a paginação em si. */
function clientComLista(paginas: { ids: number; nextPageToken?: string }[]) {
  const { __list, __get, __getProfile, __historyList } = mocks();
  let proximoId = 1;
  __list.mockReset();
  for (const pagina of paginas) {
    const messages = Array.from({ length: pagina.ids }, () => ({
      id: `m${proximoId++}`,
    }));
    __list.mockImplementationOnce(() =>
      Promise.resolve({
        data: { messages, nextPageToken: pagina.nextPageToken },
      }),
    );
  }
  __get.mockReset().mockImplementation(({ id }: { id: string }) =>
    Promise.resolve({
      data: {
        id,
        labelIds: ['INBOX'],
        payload: { headers: [] },
        snippet: '',
        internalDate: '1',
      },
    }),
  );
  __getProfile
    .mockReset()
    .mockResolvedValue({ data: { historyId: 'h-profile' } });
  __historyList.mockReset().mockResolvedValue({ data: { history: [] } });
  return { client: buildClient(), mocks: { list: __list, get: __get } };
}

/** Uma única mensagem `m1`, com `labelIds` fixas, disponível tanto para `messages.list` +
 *  `messages.get` (caminho `fetchInitial`) quanto para `history.list` (caminho `fetchIncremental`)
 *  — usado pela tabela de `fetchMessages — filtros`, que roda os dois caminhos sobre a mesma
 *  combinação de labels. */
function clientComMensagem(msg: { labelIds: string[] }) {
  const { __list, __get, __getProfile, __historyList } = mocks();
  __list.mockReset().mockResolvedValue({ data: { messages: [{ id: 'm1' }] } });
  __get.mockReset().mockResolvedValue({
    data: {
      id: 'm1',
      labelIds: msg.labelIds,
      payload: { headers: [] },
      snippet: '',
      internalDate: '1',
    },
  });
  __getProfile
    .mockReset()
    .mockResolvedValue({ data: { historyId: 'h-profile' } });
  __historyList.mockReset().mockResolvedValue({
    data: {
      history: [{ messagesAdded: [{ message: { id: 'm1' } }] }],
      historyId: 'h1',
    },
  });
  return { client: buildClient() };
}

/** Encena `history.list` devolvendo, em sequência, uma página por entrada de `paginas`
 *  (`{ messagesAdded, historyId, nextPageToken? }`). `messages.get` devolve sempre uma mensagem
 *  limpa (`INBOX`, sem ruído) — estes testes olham só para a paginação e o `historyId` devolvido. */
function clientComHistory(
  paginas: {
    messagesAdded: string[];
    historyId: string;
    nextPageToken?: string;
  }[],
) {
  const { __historyList, __get } = mocks();
  __historyList.mockReset();
  for (const pagina of paginas) {
    __historyList.mockImplementationOnce(() =>
      Promise.resolve({
        data: {
          history: [
            {
              messagesAdded: pagina.messagesAdded.map((id) => ({
                message: { id },
              })),
            },
          ],
          historyId: pagina.historyId,
          nextPageToken: pagina.nextPageToken,
        },
      }),
    );
  }
  __get.mockReset().mockImplementation(({ id }: { id: string }) =>
    Promise.resolve({
      data: {
        id,
        labelIds: ['INBOX'],
        payload: { headers: [] },
        snippet: '',
        internalDate: '1',
      },
    }),
  );
  return { client: buildClient(), mocks: { historyList: __historyList } };
}

describe('fetchInitial', () => {
  it('busca 30 dias, lidas e não lidas, sem excluir Atualizações, e pagina até 200 ids', async () => {
    const { client, mocks: m } = clientComLista([
      { ids: 100, nextPageToken: 'p2' },
      { ids: 100 },
    ]);

    const r = await client.fetchInitial('rt');

    const q = m.list.mock.calls[0][0].q as string;
    expect(q).toContain('in:inbox');
    expect(q).not.toContain('is:unread');
    expect(q).not.toContain('category:primary');
    expect(q).not.toContain('-category:updates');
    expect(q).toContain(
      '-category:promotions -category:social -category:forums',
    );
    expect(m.list.mock.calls[0][0].maxResults).toBe(100);
    expect(m.list.mock.calls[1][0].pageToken).toBe('p2');
    expect(m.get).toHaveBeenCalledTimes(200);
    expect(r.historyId).toBe('h-profile');
  });

  it('para em 200 mesmo com mais páginas', async () => {
    const { client, mocks: m } = clientComLista([
      { ids: 100, nextPageToken: 'p2' },
      { ids: 100, nextPageToken: 'p3' },
      { ids: 100 },
    ]);

    await client.fetchInitial('rt');

    expect(m.list).toHaveBeenCalledTimes(2);
  });

  it('after cobre 30 dias', async () => {
    const antes = Math.floor((Date.now() - 30 * 24 * 3600 * 1000) / 1000);
    const { client, mocks: m } = clientComLista([{ ids: 1 }]);

    await client.fetchInitial('rt');

    const match = (m.list.mock.calls[0][0].q as string).match(/after:(\d+)/);
    expect(Number(match![1])).toBeGreaterThanOrEqual(antes - 5);
  });
});

describe('fetchMessages — filtros (Promoções/Social/Fóruns/Spam e INBOX obrigatório)', () => {
  it.each([
    [['INBOX', 'CATEGORY_UPDATES'], true],
    [['INBOX', 'CATEGORY_PROMOTIONS'], false],
    [['INBOX', 'CATEGORY_SOCIAL'], false],
    [['INBOX', 'CATEGORY_FORUMS'], false],
    [['INBOX', 'SPAM'], false],
    [['SENT'], false],
    [['CATEGORY_UPDATES'], false],
    [['INBOX'], true],
  ])(
    'labelIds %p → mantida=%p (fetchInitial e fetchIncremental)',
    async (labels, mantida) => {
      const { client } = clientComMensagem({ labelIds: labels });

      const ini = await client.fetchInitial('rt');
      const inc = await client.fetchIncremental('rt', 'h0');

      expect(ini.emails).toHaveLength(mantida ? 1 : 0);
      expect(inc.emails).toHaveLength(mantida ? 1 : 0);
    },
  );
});

describe('fetchMessages — tolera falha pontual por id (item 2)', () => {
  it('404 em 1 de 3 ids em fetchInitial: descarta só aquele id, mantém os outros dois, e ainda grava o historyId (getProfile chamado)', async () => {
    const { client, mocks: m } = clientComLista([{ ids: 3 }]);
    m.get.mockReset().mockImplementation(({ id }: { id: string }) => {
      if (id === 'm2') {
        return Promise.reject(Object.assign(new Error('gone'), { code: 404 }));
      }
      return Promise.resolve({
        data: {
          id,
          labelIds: ['INBOX'],
          payload: { headers: [] },
          snippet: '',
          internalDate: '1',
        },
      });
    });

    const r = await client.fetchInitial('rt');

    expect(r.emails.map((e) => e.gmailMessageId)).toEqual(['m1', 'm3']);
    expect(mocks().__getProfile).toHaveBeenCalled();
  });

  it('401 em 1 id propaga (autenticação/quota não é tratada como mensagem apagada)', async () => {
    const { client, mocks: m } = clientComLista([{ ids: 2 }]);
    m.get.mockReset().mockImplementation(({ id }: { id: string }) => {
      if (id === 'm1') {
        return Promise.reject(
          Object.assign(new Error('unauthorized'), { code: 401 }),
        );
      }
      return Promise.resolve({
        data: {
          id,
          labelIds: ['INBOX'],
          payload: { headers: [] },
          snippet: '',
          internalDate: '1',
        },
      });
    });

    await expect(client.fetchInitial('rt')).rejects.toMatchObject({
      code: 401,
    });
  });
});

describe('fetchIncremental — paginação', () => {
  it('segue nextPageToken e devolve o historyId da última página', async () => {
    const { client, mocks: m } = clientComHistory([
      { messagesAdded: ['m1'], historyId: 'h1', nextPageToken: 'p2' },
      { messagesAdded: ['m2'], historyId: 'h2' },
    ]);

    const r = await client.fetchIncremental('rt', 'h0');

    expect(r.emails.map((e) => e.gmailMessageId)).toEqual(['m1', 'm2']);
    expect(r.historyId).toBe('h2');
    expect(m.historyList.mock.calls[1][0].pageToken).toBe('p2');
  });

  it('404 continua virando historyExpired', async () => {
    const { __historyList } = mocks();
    __historyList
      .mockReset()
      .mockRejectedValue(Object.assign(new Error('not found'), { code: 404 }));

    const r = await buildClient().fetchIncremental('rt', 'h0');

    expect(r).toEqual({ emails: [], historyId: null, historyExpired: true });
  });
});

describe('fetchIncremental — um 404 pontual de messages.get NÃO é historyExpired (item 1)', () => {
  it('history.list ok com 2 ids; get do 1º rejeita 404 → mantém o 2º e-mail, historyExpired false, historyId da página', async () => {
    const { __historyList, __get } = mocks();
    __historyList.mockReset().mockResolvedValue({
      data: {
        history: [
          {
            messagesAdded: [
              { message: { id: 'm1' } },
              { message: { id: 'm2' } },
            ],
          },
        ],
        historyId: 'h-pagina',
      },
    });
    __get.mockReset().mockImplementation(({ id }: { id: string }) => {
      if (id === 'm1') {
        return Promise.reject(
          Object.assign(new Error('not found'), { code: 404 }),
        );
      }
      return Promise.resolve({
        data: {
          id,
          labelIds: ['INBOX'],
          payload: { headers: [] },
          snippet: '',
          internalDate: '1',
        },
      });
    });

    const r = await buildClient().fetchIncremental('rt', 'h0');

    expect(r.emails.map((e) => e.gmailMessageId)).toEqual(['m2']);
    expect(r.historyExpired).toBe(false);
    expect(r.historyId).toBe('h-pagina');
  });
});

describe('fetchIncremental — teto de páginas (item 3)', () => {
  it('para em INCREMENTAL_MAX_PAGINAS (20) páginas mesmo havendo mais, devolvendo o historyId da última lida', async () => {
    const totalPaginasDisponiveis = 21;
    const paginas = Array.from({ length: totalPaginasDisponiveis }, (_, i) => ({
      messagesAdded: [`m${i + 1}`],
      historyId: `h${i + 1}`,
      nextPageToken: i + 1 < totalPaginasDisponiveis ? `p${i + 2}` : undefined,
    }));
    const { client, mocks: m } = clientComHistory(paginas);

    const r = await client.fetchIncremental('rt', 'h0');

    expect(m.historyList).toHaveBeenCalledTimes(20);
    expect(r.historyId).toBe('h20');
    expect(r.historyExpired).toBe(false);
  });
});

describe('fetchIncremental — dedupe, labelIds e página inicial vazia (item 4)', () => {
  it('deduplica ids repetidos entre páginas de history.list: um único messages.get por id', async () => {
    const { client } = clientComHistory([
      { messagesAdded: ['m1'], historyId: 'h1', nextPageToken: 'p2' },
      { messagesAdded: ['m1', 'm2'], historyId: 'h2' },
    ]);

    await client.fetchIncremental('rt', 'h0');

    const idsChamados = (mocks().__get.mock.calls as [{ id: string }][]).map(
      ([{ id }]) => id,
    );
    expect(idsChamados.sort()).toEqual(['m1', 'm2']);
  });

  it('copia labelIds da mensagem para FetchedEmail', async () => {
    const { __historyList, __get } = mocks();
    __historyList.mockReset().mockResolvedValue({
      data: {
        history: [{ messagesAdded: [{ message: { id: 'm1' } }] }],
        historyId: 'h1',
      },
    });
    __get.mockReset().mockResolvedValue({
      data: {
        id: 'm1',
        labelIds: ['INBOX', 'CATEGORY_UPDATES', 'IMPORTANT'],
        payload: { headers: [] },
        snippet: '',
        internalDate: '1',
      },
    });

    const r = await buildClient().fetchIncremental('rt', 'h0');

    expect(r.emails[0].labelIds).toEqual([
      'INBOX',
      'CATEGORY_UPDATES',
      'IMPORTANT',
    ]);
  });

  it('labelIds ausente na resposta do get: descarta a mensagem sem crashar', async () => {
    const { __historyList, __get } = mocks();
    __historyList.mockReset().mockResolvedValue({
      data: {
        history: [{ messagesAdded: [{ message: { id: 'm1' } }] }],
        historyId: 'h1',
      },
    });
    __get.mockReset().mockResolvedValue({
      data: {
        id: 'm1',
        payload: { headers: [] },
        snippet: '',
        internalDate: '1',
      },
    });

    const r = await buildClient().fetchIncremental('rt', 'h0');

    expect(r.emails).toEqual([]);
  });

  it('1ª página sem "history" mas com nextPageToken continua para a 2ª', async () => {
    const { __historyList, __get } = mocks();
    __historyList
      .mockReset()
      .mockImplementationOnce(() =>
        Promise.resolve({ data: { nextPageToken: 'p2', historyId: 'h1' } }),
      )
      .mockImplementationOnce(() =>
        Promise.resolve({
          data: {
            history: [{ messagesAdded: [{ message: { id: 'm1' } }] }],
            historyId: 'h2',
          },
        }),
      );
    __get.mockReset().mockResolvedValue({
      data: {
        id: 'm1',
        labelIds: ['INBOX'],
        payload: { headers: [] },
        snippet: '',
        internalDate: '1',
      },
    });

    const r = await buildClient().fetchIncremental('rt', 'h0');

    expect(__historyList).toHaveBeenCalledTimes(2);
    expect(r.emails.map((e) => e.gmailMessageId)).toEqual(['m1']);
    expect(r.historyId).toBe('h2');
  });
});

describe('fetchInitial — regressão "servidor já filtrou promoções" (item 4)', () => {
  it('200 ids trazidos, todos com label de ruído: 0 e-mails, e messages.list não é chamado uma 3ª vez', async () => {
    const { client, mocks: m } = clientComLista([
      { ids: 100, nextPageToken: 'p2' },
      { ids: 100 },
    ]);
    m.get.mockReset().mockImplementation(({ id }: { id: string }) =>
      Promise.resolve({
        data: {
          id,
          labelIds: ['CATEGORY_PROMOTIONS'],
          payload: { headers: [] },
          snippet: '',
          internalDate: '1',
        },
      }),
    );

    const r = await client.fetchInitial('rt');

    expect(r.emails).toHaveLength(0);
    expect(m.list).toHaveBeenCalledTimes(2);
  });
});

describe('GmailApiClient — arquivar/excluir', () => {
  beforeEach(() => {
    const { __modify, __trash } = mocks();
    __modify.mockReset().mockResolvedValue({ data: {} });
    __trash.mockReset().mockResolvedValue({ data: {} });
  });

  it('arquivar chama messages.modify removendo só o label INBOX (reversível)', async () => {
    await buildClient().arquivar('rt-123', 'msg-1');

    const { __modify, __trash } = mocks();
    expect(__modify).toHaveBeenCalledWith({
      userId: 'me',
      id: 'msg-1',
      requestBody: { removeLabelIds: ['INBOX'] },
    });
    expect(__trash).not.toHaveBeenCalled();
  });

  it('excluir chama messages.trash (reversível), nunca messages.delete', async () => {
    await buildClient().excluir('rt-123', 'msg-1');

    const { __trash } = mocks();
    expect(__trash).toHaveBeenCalledWith({ userId: 'me', id: 'msg-1' });
  });
});

function base64url(texto: string): string {
  return Buffer.from(texto, 'utf8').toString('base64url');
}

/** Mocka `users.messages.get` para devolver `{ data: { payload, snippet: 's' } }` — mesma técnica
 *  usada nos testes de `fetchFullBody` acima, extraída para reuso pelos testes de
 *  `fetchFullBodyComAnexos`/`pareceHtml`. */
function clientComPayload(payload: unknown) {
  const { __get } = mocks();
  __get.mockReset().mockResolvedValue({ data: { payload, snippet: 's' } });
  return buildClient();
}

describe('GmailApiClient.fetchFullBody — corpo completo do e-mail (item 2: HTML não pode virar snippet cortado)', () => {
  beforeEach(() => {
    const { __get } = mocks();
    __get.mockReset();
  });

  it('e-mail com text/plain: devolve o texto puro direto, sem tocar no HTML nem no snippet', async () => {
    const { __get } = mocks();
    __get.mockResolvedValue({
      data: {
        payload: {
          mimeType: 'multipart/alternative',
          parts: [
            {
              mimeType: 'text/plain',
              body: { data: base64url('Olá, tudo bem?') },
            },
            {
              mimeType: 'text/html',
              body: { data: base64url('<p>Olá, tudo bem?</p>') },
            },
          ],
        },
        snippet: 'Olá, tudo...',
      },
    });

    const result = await buildClient().fetchFullBody('rt-123', 'msg-1');

    expect(result).toEqual({ texto: 'Olá, tudo bem?', ehPreview: false });
  });

  it(
    'e-mail HTML-only (sem text/plain — a maioria dos e-mails reais): converte o HTML em texto ' +
      'legível, em vez de cair no snippet de ~200 caracteres',
    async () => {
      const { __get } = mocks();
      const html =
        '<html><body>' +
        '<p>Olá Maria,</p>' +
        '<p>Sua fatura de <b>R$ 150,00</b> vence amanhã. Categorias: A &amp; B.</p>' +
        '<ul><li>Item um</li><li>Item dois</li></ul>' +
        '<script>trackClick();</script>' +
        '<style>.x{color:red}</style>' +
        '<p>Atenciosamente,<br>Equipe Financeira</p>' +
        '</body></html>';
      __get.mockResolvedValue({
        data: {
          payload: { mimeType: 'text/html', body: { data: base64url(html) } },
          snippet: 'Olá Maria, Sua fatura de R$ 150,00 vence amanhã...',
        },
      });

      const result = await buildClient().fetchFullBody('rt-123', 'msg-1');

      // Provado por execução, não suposto: não é null, não é o snippet truncado, não é o HTML cru.
      expect(result.texto).not.toBeNull();
      expect(result.texto).not.toContain('<p>');
      expect(result.texto).not.toContain('<script>');
      expect(result.texto).not.toContain('trackClick');
      expect(result.texto).not.toContain('.x{color:red}');
      expect(result.texto).toContain('Olá Maria,');
      expect(result.texto).toContain(
        'Sua fatura de R$ 150,00 vence amanhã. Categorias: A & B.',
      );
      expect(result.texto).toContain('Item um');
      expect(result.texto).toContain('Item dois');
      expect(result.texto).toContain('Equipe Financeira');
      expect(result.ehPreview).toBe(false);
      // Estritamente mais informativo que o snippet que a UI mostrava antes.
      expect(result.texto.length).toBeGreaterThan(
        'Olá Maria, Sua fatura de R$ 150,00 vence amanhã...'.length,
      );
    },
  );

  it('e-mail sem text/plain E sem text/html (ex.: só anexo): cai no snippet, mas marca ehPreview', async () => {
    const { __get } = mocks();
    __get.mockResolvedValue({
      data: {
        payload: {
          mimeType: 'application/pdf',
          body: { data: base64url('%PDF-binary-ish') },
        },
        snippet: 'Segue o anexo solicitado',
      },
    });

    const result = await buildClient().fetchFullBody('rt-123', 'msg-1');

    expect(result).toEqual({
      texto: 'Segue o anexo solicitado',
      ehPreview: true,
    });
  });

  it('busca o HTML corretamente dentro de multipart/mixed com sub-multipart/alternative aninhado', async () => {
    const { __get } = mocks();
    __get.mockResolvedValue({
      data: {
        payload: {
          mimeType: 'multipart/mixed',
          parts: [
            {
              mimeType: 'multipart/alternative',
              parts: [
                {
                  mimeType: 'text/html',
                  body: { data: base64url('<div>Corpo aninhado</div>') },
                },
              ],
            },
            { mimeType: 'application/pdf', body: { data: base64url('anexo') } },
          ],
        },
        snippet: 'Corpo aninhado',
      },
    });

    const result = await buildClient().fetchFullBody('rt-123', 'msg-1');

    expect(result).toEqual({ texto: 'Corpo aninhado', ehPreview: false });
  });
});

describe('GmailApiClient.pareceHtml', () => {
  it.each([
    '<html>',
    '<HTML>',
    '<html lang="pt-br">',
    '\uFEFF   <!doctype html>',
    '<br>',
    '<br/>',
    '<div\nclass="x">',
    'Preheader de texto\n<html>',
    '<body>',
    '<!-- x -->',
    // Word/Outlook: doctype legado (atributos "HTML PUBLIC ...", não nome=valor) seguido de
    // xmlns com ':' no nome do atributo — ambos regrediram numa versão anterior do regex.
    '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN">\r\n' +
      '<html xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office">\r\n' +
      '<head>',
    '<!--[if mso]>', // comentário condicional do Outlook, sem espaço após os hífens
    '<html xmlns:v="urn:schemas-microsoft-com:vml">',
    '<table border cellpadding=0>', // atributo booleano ("border") antes de um atributo com '='
    '<div class = "x">',
    // janela de 340 chars: tag iniciando em 295 ainda cabe inteira (fecha bem antes de 340)
    `${'x'.repeat(295)}<html>`,
  ])('detects %p as HTML', (t) => {
    expect(GmailApiClient.pareceHtml(t)).toBe(true);
  });

  it.each([
    'O preço <p 10 reais',
    'Se x<p então y > z',
    'De: Paulo <p@empresa.com>',
    '<br@empresa.com.br>',
    'Olá, segue sua fatura.',
    JSON.stringify({ a: 1, b: 'texto' }),
    '# Título\n\nAlgum **markdown** com [link](http://x.com)',
    // janela de 340 chars: tag iniciando em 341 cai inteira fora da fatia examinada
    `${'x'.repeat(341)}<html>`,
  ])('does NOT detect %p as HTML (genuine prose, not a real tag)', (t) => {
    expect(GmailApiClient.pareceHtml(t)).toBe(false);
  });
});

describe('GmailApiClient.fetchFullBodyComAnexos', () => {
  beforeEach(() => {
    mocks().__get.mockReset();
  });

  it('converts a text/plain part that is actually HTML', async () => {
    const html =
      '<html><body><table><tr><td>Vencimento: 17/09<br>Valor total: 520,61</td></tr></table></body></html>';
    const payload = { mimeType: 'text/plain', body: { data: base64url(html) } };

    const r = await clientComPayload(payload).fetchFullBodyComAnexos(
      'rt',
      'm1',
    );

    expect(r.texto).toContain('Vencimento: 17/09\nValor total: 520,61');
    expect(r.anexos).toEqual([]);
    expect(r.ehPreview).toBe(false);
  });

  it('lists attachment metadata without downloading, including octet-stream .PDF', async () => {
    const payload = {
      mimeType: 'multipart/mixed',
      parts: [
        { mimeType: 'text/plain', body: { data: base64url('oi') } },
        {
          mimeType: 'application/octet-stream',
          filename: 'Fatura_082026.PDF',
          body: { attachmentId: 'att1', size: 12345 },
        },
        {
          mimeType: 'image/png',
          filename: 'logo.png',
          body: { attachmentId: 'att2', size: 10 },
        },
      ],
    };

    const r = await clientComPayload(payload).fetchFullBodyComAnexos(
      'rt',
      'm1',
    );

    expect(r.anexos).toEqual([
      {
        filename: 'Fatura_082026.PDF',
        mimeType: 'application/octet-stream',
        size: 12345,
        attachmentId: 'att1',
      },
      {
        filename: 'logo.png',
        mimeType: 'image/png',
        size: 10,
        attachmentId: 'att2',
      },
    ]);
  });

  it('percorre multipart/mixed > multipart/related aninhado: imagem inline (sem filename, com Content-Id) fica de fora, PDF em outro nível entra', async () => {
    const payload = {
      mimeType: 'multipart/mixed',
      parts: [
        {
          mimeType: 'multipart/related',
          parts: [
            {
              mimeType: 'text/html',
              body: { data: base64url('<p>Corpo</p><img src="cid:logo">') },
            },
            {
              mimeType: 'image/png',
              filename: '',
              headers: [{ name: 'Content-ID', value: '<logo>' }],
              body: { attachmentId: 'inline-att', size: 500 },
            },
          ],
        },
        {
          mimeType: 'application/pdf',
          filename: 'fatura.pdf',
          body: { attachmentId: 'att-pdf', size: 999 },
        },
      ],
    };

    const r = await clientComPayload(payload).fetchFullBodyComAnexos(
      'rt',
      'm1',
    );

    expect(r.anexos).toEqual([
      {
        filename: 'fatura.pdf',
        mimeType: 'application/pdf',
        size: 999,
        attachmentId: 'att-pdf',
      },
    ]);
  });

  it('anexo sem body.size vira size 0, em vez de undefined', async () => {
    const payload = {
      mimeType: 'multipart/mixed',
      parts: [
        { mimeType: 'text/plain', body: { data: base64url('oi') } },
        {
          mimeType: 'application/pdf',
          filename: 'sem-tamanho.pdf',
          body: { attachmentId: 'att-sem-size' },
        },
      ],
    };

    const r = await clientComPayload(payload).fetchFullBodyComAnexos(
      'rt',
      'm1',
    );

    expect(r.anexos).toEqual([
      {
        filename: 'sem-tamanho.pdf',
        mimeType: 'application/pdf',
        size: 0,
        attachmentId: 'att-sem-size',
      },
    ]);
  });

  it('não converte texto plano genuíno mesmo com anexos presentes', async () => {
    const payload = {
      mimeType: 'multipart/mixed',
      parts: [
        {
          mimeType: 'text/plain',
          body: { data: base64url('Olá, segue sua fatura em anexo.') },
        },
        {
          mimeType: 'application/pdf',
          filename: 'fatura.pdf',
          body: { attachmentId: 'att1', size: 999 },
        },
      ],
    };

    const r = await clientComPayload(payload).fetchFullBodyComAnexos(
      'rt',
      'm1',
    );

    expect(r.texto).toBe('Olá, segue sua fatura em anexo.');
    expect(r.ehPreview).toBe(false);
    expect(r.anexos).toEqual([
      {
        filename: 'fatura.pdf',
        mimeType: 'application/pdf',
        size: 999,
        attachmentId: 'att1',
      },
    ]);
  });
});

describe('GmailApiClient.fetchFullBody — wrapper fino sobre fetchFullBodyComAnexos', () => {
  it('devolve só { texto, ehPreview }, sem o campo anexos, mantendo o contrato antigo', async () => {
    const payload = {
      mimeType: 'multipart/mixed',
      parts: [
        { mimeType: 'text/plain', body: { data: base64url('Olá, tudo bem?') } },
        {
          mimeType: 'application/pdf',
          filename: 'fatura.pdf',
          body: { attachmentId: 'att1', size: 999 },
        },
      ],
    };

    const result = await clientComPayload(payload).fetchFullBody('rt', 'm1');

    expect(result).toEqual({ texto: 'Olá, tudo bem?', ehPreview: false });
    expect(result).not.toHaveProperty('anexos');
  });
});

/** Mocka `users.messages.attachments.get` para devolver `{ data: { data: dataBase64url } }` — o
 *  formato que o Gmail usa para o conteúdo binário de um anexo. */
function clientComAttachment(dataBase64url: string) {
  const { __attachmentsGet } = mocks();
  __attachmentsGet
    .mockReset()
    .mockResolvedValue({ data: { data: dataBase64url } });
  return buildClient();
}

/** Mocka `users.messages.attachments.get` para rejeitar com `erro` — usado para verificar que um
 *  erro do Gmail (não do `pdf-parse`) PROPAGA para o chamador classificar, em vez de virar `null`
 *  como "PDF ilegível". */
function clientComAttachmentErro(erro: unknown) {
  const { __attachmentsGet } = mocks();
  __attachmentsGet.mockReset().mockRejectedValue(erro);
  return buildClient();
}

// PDF mínimo válido com uma única linha de texto, gerado à mão (sem xref table: os leitores PDF
// tolerantes — incluindo o pdfjs-dist usado pelo pdf-parse — reconstroem a partir dos objetos
// `N 0 obj` quando o `trailer` aponta para o catálogo). Confirmado localmente que o pdf-parse 2.4.5
// extrai "Total da fatura R$ 1.234,56" deste buffer.
const PDF_MINIMO = Buffer.from(`%PDF-1.4
1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 300 100]/Contents 4 0 R/Resources<</Font<</F1 5 0 R>>>>>>endobj
4 0 obj<</Length 60>>stream
BT /F1 12 Tf 10 50 Td (Total da fatura R$ 1.234,56) Tj ET
endstream
endobj
5 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj
trailer<</Root 1 0 R>>`);

// PDF real de 200x100, uma página em branco, protegido por senha ("senha123", usuário e
// proprietário), gerado com pypdf 6.18.0 (algoritmo RC4-128 — o algoritmo AES exigiria o pacote
// `cryptography`, indisponível no ambiente usado para gerar a fixture; RC4-128 já é suficiente
// para exercitar o caminho real de `PasswordException` do pdf-parse/pdfjs-dist, que é o que este
// teste verifica). Script usado:
//   from pypdf import PdfWriter
//   writer = PdfWriter()
//   writer.add_blank_page(width=200, height=100)
//   writer.encrypt(user_password="senha123", owner_password="senha123", algorithm="RC4-128")
//   writer.write("encrypted.pdf")
// Confirmado localmente (fora do Jest) que `new PDFParse({ data }).getText()` rejeita com
// `PasswordException` — "No password given" — para este buffer.
const PDF_CIFRADO_BASE64URL =
  'JVBERi0xLjMKJeLjz9MKMSAwIG9iago8PAovUHJvZHVjZXIgPGRiNmMwZGI1NjQ-Cj4-CmVuZG9iagoyIDAgb2JqCjw8Ci' +
  '9UeXBlIC9QYWdlcwovQ291bnQgMQovS2lkcyBbIDQgMCBSIF0KPj4KZW5kb2JqCjMgMCBvYmoKPDwKL1R5cGUgL0NhdGFsb2' +
  'cKL1BhZ2VzIDIgMCBSCj4-CmVuZG9iago0IDAgb2JqCjw8Ci9UeXBlIC9QYWdlCi9SZXNvdXJjZXMgPDwKPj4KL01lZGlhQm' +
  '94IFsgMC4wIDAuMCAyMDAgMTAwIF0KL1BhcmVudCAyIDAgUgo-PgplbmRvYmoKNSAwIG9iago8PAovViAyCi9SIDMKL0xlbm' +
  'd0aCAxMjgKL1AgNDI5NDk2NzI5MgovRmlsdGVyIC9TdGFuZGFyZAovTyA8YmYzZGFkMGM3OWIyZmVhZTdiMjVjZjEzNDIxND' +
  'c2YmM0ZWFjOTRmODQxOGZlM2E2M2E3NzRiNWJkNjA3NTJiMT4KL1UgPGUwZjBkYjU4MzYyODlhMjExMTYzZDQzNDE0MWQwMD' +
  'gzMjhiZjRlNWU0ZTc1OGE0MTY0MDA0ZTU2ZmZmYTAxMDg-Cj4-CmVuZG9iagp4cmVmCjAgNgowMDAwMDAwMDAwIDY1NTM1IG' +
  'YgCjAwMDAwMDAwMTUgMDAwMDAgbiAKMDAwMDAwMDA1OSAwMDAwMCBuIAowMDAwMDAwMTE4IDAwMDAwIG4gCjAwMDAwMDAxNj' +
  'cgMDAwMDAgbiAKMDAwMDAwMDI2MSAwMDAwMCBuIAp0cmFpbGVyCjw8Ci9TaXplIDYKL1Jvb3QgMyAwIFIKL0luZm8gMSAwIF' +
  'IKL0lEIFsgPDY0NjE2MTM2MzU2NjM3MzY2NjY1MzkzNzY0NjUzODM1MzI2MTMxMzA2NjY0MzMzMTMyMzE2NTYyMzYzNjMzMz' +
  'M-IDw2NDYxNjEzNjM1NjYzNzM2NjY2NTM5Mzc2NDY1MzgzNTMyNjEzMTMwNjY2NDMzMzEzMjMxNjU2MjM2MzYzMzMzPiBdCi' +
  '9FbmNyeXB0IDUgMCBSCj4-CnN0YXJ0eHJlZgo0NzYKJSVFT0YK';

describe('GmailApiClient.fetchPdfAttachmentText', () => {
  const anexo = {
    filename: 'f.pdf',
    mimeType: 'application/pdf',
    size: PDF_MINIMO.length,
    attachmentId: 'att1',
  };

  it('extracts text from a PDF attachment', async () => {
    const client = clientComAttachment(PDF_MINIMO.toString('base64url'));

    await expect(
      client.fetchPdfAttachmentText('rt', 'm1', anexo),
    ).resolves.toContain('Total da fatura');
  });

  it('returns null for an unreadable PDF', async () => {
    const client = clientComAttachment(
      Buffer.from('nao e pdf').toString('base64url'),
    );

    await expect(
      client.fetchPdfAttachmentText('rt', 'm1', anexo),
    ).resolves.toBeNull();
  });

  it('returns null for a REAL password-protected PDF fixture, destroying the parser exactly once', async () => {
    const client = clientComAttachment(PDF_CIFRADO_BASE64URL);
    const destroySpy = jest.spyOn(PDFParse.prototype, 'destroy');
    const warnSpy = jest
      .spyOn(Logger.prototype, 'warn')
      .mockImplementation(() => undefined);

    await expect(
      client.fetchPdfAttachmentText('rt', 'm1', anexo),
    ).resolves.toBeNull();

    expect(destroySpy).toHaveBeenCalledTimes(1);
    // Confirma que este PDF cifrado é resolvido pelo ramo conhecido (`PasswordException`), não
    // pelo ramo de erro desconhecido — senão este teste estaria testando `warn`, não a senha.
    expect(warnSpy).not.toHaveBeenCalled();
    destroySpy.mockRestore();
    warnSpy.mockRestore();
  });

  it(
    'logs the unknown error (name + message) at warn level before returning null, so an infra ' +
      'error is not indistinguishable from an unreadable PDF',
    async () => {
      const client = clientComAttachment(PDF_MINIMO.toString('base64url'));
      const warnSpy = jest
        .spyOn(Logger.prototype, 'warn')
        .mockImplementation(() => undefined);
      const getTextSpy = jest
        .spyOn(PDFParse.prototype, 'getText')
        .mockRejectedValueOnce(new Error('Setting up fake worker failed'));

      await expect(
        client.fetchPdfAttachmentText('rt', 'm1', anexo),
      ).resolves.toBeNull();

      expect(warnSpy).toHaveBeenCalledTimes(1);
      expect(warnSpy.mock.calls[0][0]).toEqual(
        expect.stringContaining('fake worker'),
      );

      getTextSpy.mockRestore();
      warnSpy.mockRestore();
    },
  );

  it('returns null and destroys the parser exactly once when getText never resolves (timeout)', async () => {
    const client = clientComAttachment(PDF_MINIMO.toString('base64url'));
    const getTextSpy = jest
      .spyOn(PDFParse.prototype, 'getText')
      .mockReturnValueOnce(new Promise(() => undefined));
    const destroySpy = jest.spyOn(PDFParse.prototype, 'destroy');

    await expect(
      client.fetchPdfAttachmentText('rt', 'm1', anexo, 20),
    ).resolves.toBeNull();

    expect(destroySpy).toHaveBeenCalledTimes(1);

    getTextSpy.mockRestore();
    destroySpy.mockRestore();
  });

  it('escolherPdf picks by mimeType or extension within size cap', () => {
    expect(
      GmailApiClient.escolherPdf([
        {
          filename: 'x.PDF',
          mimeType: 'application/octet-stream',
          size: 10,
          attachmentId: 'a',
        },
      ])?.attachmentId,
    ).toBe('a');
    expect(
      GmailApiClient.escolherPdf([
        {
          filename: 'big.pdf',
          mimeType: 'application/pdf',
          size: 6 * 1024 * 1024,
          attachmentId: 'b',
        },
      ]),
    ).toBeNull();
    expect(
      GmailApiClient.escolherPdf([
        {
          filename: 'logo.png',
          mimeType: 'image/png',
          size: 1,
          attachmentId: 'c',
        },
      ]),
    ).toBeNull();
  });

  it('propagates a gaxios error from attachments.get (classified by the caller)', async () => {
    const client = clientComAttachmentErro(
      Object.assign(new Error('boom'), {
        response: { status: 503 },
        code: 503,
        config: {},
      }),
    );

    await expect(
      client.fetchPdfAttachmentText('rt', 'm1', anexo),
    ).rejects.toBeDefined();
  });
});

/** Mocka `users.labels.list` (com `labels`, cada um `{ id, name }`) e `users.messages.list` (com
 *  `messages`, cada um `{ id }`) — usado pelos testes de `listarIdsComMarcador`. */
function clientComLabels(
  labels: { id: string; name: string }[],
  messages: { id: string }[],
) {
  const { __labelsList, __list } = mocks();
  __labelsList.mockReset().mockResolvedValue({ data: { labels } });
  __list.mockReset().mockResolvedValue({ data: { messages } });
  return buildClient();
}

// Fixture NFD real (não simulada): "finanças" com o "ç" DECOMPOSTO em "c" + U+0327 (COMBINING
// CEDILLA), em vez do "ç" precomposto (U+00E7) usado no resto do arquivo. `.normalize('NFD')`
// gera essa forma a partir da string precomposta — confirmado abaixo, no próprio arquivo, que o
// resultado NÃO é byte-a-byte igual à string precomposta (a decomposição é real, não um no-op),
// e que comparar com `.normalize('NFC')` as torna iguais de novo, exatamente o que
// `listarIdsComMarcador` faz internamente para casar o dois.
const NOME_MARCADOR_NFD = 'sincro/finanças'.normalize('NFD');

describe('GmailApiClient.listarIdsComMarcador', () => {
  it('sanity check: a fixture NFD é uma decomposição de verdade, não um no-op', () => {
    expect(NOME_MARCADOR_NFD).not.toBe('sincro/finanças');
    expect(NOME_MARCADOR_NFD).toContain('̧'); // COMBINING CEDILLA
    expect(NOME_MARCADOR_NFD.normalize('NFC')).toBe('sincro/finanças');
  });

  it('resolves the label from a REAL NFD-normalized name (combining cedilla, U+0327), case-insensitive', async () => {
    const client = clientComLabels(
      [{ id: 'Label_7', name: NOME_MARCADOR_NFD.toUpperCase() }],
      [{ id: 'm1' }, { id: 'm2' }],
    );

    await expect(client.listarIdsComMarcador('rt')).resolves.toEqual({
      labelId: 'Label_7',
      ids: new Set(['m1', 'm2']),
    });
    expect(mocks().__list).toHaveBeenCalledWith({
      userId: 'me',
      labelIds: ['Label_7'],
      q: 'newer_than:90d',
      maxResults: 100,
    });
  });

  it('NEGATIVO: um label sem cedilha nenhuma ("sincro/financas") não casa com "Sincro/Finanças" — nenhuma chamada a messages.list', async () => {
    const client = clientComLabels(
      [{ id: 'Label_9', name: 'sincro/financas' }],
      [],
    );

    await expect(client.listarIdsComMarcador('rt')).resolves.toEqual({
      labelId: null,
      ids: new Set(),
    });
    expect(mocks().__list).not.toHaveBeenCalled();
  });

  it('returns an empty set without extra calls when the label does not exist', async () => {
    const client = clientComLabels([{ id: 'Label_1', name: 'Outro' }], []);

    await expect(client.listarIdsComMarcador('rt')).resolves.toEqual({
      labelId: null,
      ids: new Set(),
    });
    expect(mocks().__list).not.toHaveBeenCalled();
  });

  it('messages.list devolvendo { messages: undefined } vira um Set vazio, com o labelId resolvido mesmo assim', async () => {
    const { __labelsList, __list } = mocks();
    __labelsList.mockReset().mockResolvedValue({
      data: { labels: [{ id: 'Label_7', name: 'Sincro/Finanças' }] },
    });
    __list.mockReset().mockResolvedValue({ data: { messages: undefined } });

    await expect(buildClient().listarIdsComMarcador('rt')).resolves.toEqual({
      labelId: 'Label_7',
      ids: new Set(),
    });
  });

  it('entradas de messages.list sem id de verdade (só threadId, ou id null) são descartadas do Set', async () => {
    const { __labelsList, __list } = mocks();
    __labelsList.mockReset().mockResolvedValue({
      data: { labels: [{ id: 'Label_7', name: 'Sincro/Finanças' }] },
    });
    __list.mockReset().mockResolvedValue({
      data: { messages: [{ threadId: 't' }, { id: null }, { id: 'm-valido' }] },
    });

    await expect(buildClient().listarIdsComMarcador('rt')).resolves.toEqual({
      labelId: 'Label_7',
      ids: new Set(['m-valido']),
    });
  });

  it('chama users.labels.list exatamente uma vez, com { userId: "me" }', async () => {
    const client = clientComLabels(
      [{ id: 'Label_7', name: 'Sincro/Finanças' }],
      [{ id: 'm1' }],
    );

    await client.listarIdsComMarcador('rt');

    expect(mocks().__labelsList).toHaveBeenCalledTimes(1);
    expect(mocks().__labelsList).toHaveBeenCalledWith({ userId: 'me' });
  });
});
