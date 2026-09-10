import { GmailApiClient } from './gmail-api-client.service';

jest.mock('googleapis', () => {
  const get = jest.fn();
  const send = jest.fn().mockResolvedValue({ data: {} });
  const list = jest.fn().mockResolvedValue({ data: { messages: [] } });
  const modify = jest.fn().mockResolvedValue({ data: {} });
  const trash = jest.fn().mockResolvedValue({ data: {} });
  const getProfile = jest.fn().mockResolvedValue({ data: { historyId: 'h1' } });
  const historyList = jest.fn().mockResolvedValue({ data: { history: [] } });
  return {
    google: {
      gmail: jest.fn(() => ({
        users: {
          messages: { get, send, list, modify, trash },
          getProfile,
          history: { list: historyList },
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
  };
});

function mocks() {
  return jest.requireMock('googleapis') as {
    __get: jest.Mock;
    __send: jest.Mock;
    __list: jest.Mock;
    __modify: jest.Mock;
    __trash: jest.Mock;
    __getProfile: jest.Mock;
    __historyList: jest.Mock;
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

describe('GmailApiClient — filtro de ruído (Promoções/Social/Atualizações/Fóruns/Spam)', () => {
  beforeEach(() => {
    const { __get, __list, __getProfile, __historyList } = mocks();
    __get.mockReset();
    __list.mockReset().mockResolvedValue({ data: { messages: [] } });
    __getProfile.mockReset().mockResolvedValue({ data: { historyId: 'h-new' } });
    __historyList.mockReset().mockResolvedValue({ data: { history: [] } });
  });

  it('fetchInitialUnread busca com in:inbox (não category:primary, que depende do usuário ter as abas do Gmail ativadas)', async () => {
    await buildClient().fetchInitialUnread('rt-123');

    const { __list } = mocks();
    expect(__list).toHaveBeenCalledWith(expect.objectContaining({ q: expect.stringContaining('in:inbox') }));
    expect(__list).toHaveBeenCalledWith(
      expect.objectContaining({ q: expect.not.stringContaining('category:primary') }),
    );
  });

  it('fetchInitialUnread exclui Promoções/Social/Atualizações/Fóruns já no `q`, para o cap de 50 do Gmail não ser gasto com ruído', async () => {
    await buildClient().fetchInitialUnread('rt-123');

    const { __list } = mocks();
    const q = (__list.mock.calls[0][0] as { q: string }).q;
    expect(q).toContain('-category:promotions');
    expect(q).toContain('-category:social');
    expect(q).toContain('-category:updates');
    expect(q).toContain('-category:forums');
  });

  it('REGRESSÃO: com 50+ promoções não lidas e poucas mensagens reais, fetchInitialUnread ainda devolve as reais (o cap de 50 do Gmail é aplicado ANTES do filtro por labelIds do nosso lado)', async () => {
    const { __list, __get } = mocks();

    // Simula o comportamento real da API do Gmail: `messages.list` aplica o `q` (inclusive as
    // exclusões negativas de categoria) NO SERVIDOR, antes de truncar em `maxResults`. Se o `q`
    // enviado pelo código não excluir as categorias de ruído, esta simulação devolve as 50
    // promoções e nenhuma mensagem real sobra — exatamente o sintoma da regressão relatada.
    const contaCompleta: { id: string; categoria: string | null }[] = [
      ...Array.from({ length: 55 }, (_, i) => ({ id: `promo-${i}`, categoria: 'promotions' })),
      { id: 'real-1', categoria: null },
      { id: 'real-2', categoria: null },
      { id: 'real-3', categoria: null },
    ];
    __list.mockImplementation(({ q }: { q: string }) => {
      const categoriasExcluidas = [...q.matchAll(/-category:(\w+)/g)].map((m) => m[1]);
      const combinam = contaCompleta.filter(
        (m) => m.categoria === null || !categoriasExcluidas.includes(m.categoria),
      );
      return Promise.resolve({ data: { messages: combinam.slice(0, 50).map((m) => ({ id: m.id })) } });
    });
    __get.mockImplementation(({ id }: { id: string }) => {
      const labelIds = id.startsWith('promo-') ? ['CATEGORY_PROMOTIONS', 'UNREAD', 'INBOX'] : ['UNREAD', 'INBOX'];
      return Promise.resolve({
        data: {
          labelIds,
          payload: { headers: [{ name: 'From', value: 'x@example.com' }, { name: 'Subject', value: 'Assunto' }] },
          snippet: 'trecho',
          internalDate: '1000',
        },
      });
    });

    const result = await buildClient().fetchInitialUnread('rt-123');

    expect(result.emails.map((e) => e.gmailMessageId).sort()).toEqual(['real-1', 'real-2', 'real-3']);
  });

  it('fetchInitialUnread descarta Promoções/Social/Atualizações/Fóruns/Spam pelas labelIds — mesma lista negra do fetchIncremental', async () => {
    const { __list, __get } = mocks();
    __list.mockResolvedValue({
      data: {
        messages: [{ id: 'promo-1' }, { id: 'spam-1' }, { id: 'principal-1' }],
      },
    });
    __get.mockImplementation(({ id }: { id: string }) => {
      const labelsByMessage: Record<string, string[]> = {
        'promo-1': ['CATEGORY_PROMOTIONS', 'UNREAD', 'INBOX'],
        'spam-1': ['SPAM', 'UNREAD'],
        'principal-1': ['CATEGORY_PERSONAL', 'UNREAD', 'INBOX'],
      };
      return Promise.resolve({
        data: {
          labelIds: labelsByMessage[id],
          payload: { headers: [{ name: 'From', value: 'x@example.com' }, { name: 'Subject', value: 'Assunto' }] },
          snippet: 'trecho',
          internalDate: '1000',
        },
      });
    });

    const result = await buildClient().fetchInitialUnread('rt-123');

    expect(result.emails.map((e) => e.gmailMessageId)).toEqual(['principal-1']);
  });

  it('fetchIncremental descarta mensagens de Promoções/Social/Atualizações/Fóruns pelas labelIds', async () => {
    const { __historyList, __get } = mocks();
    __historyList.mockResolvedValue({
      data: {
        historyId: 'h2',
        history: [
          { messagesAdded: [{ message: { id: 'promo-1' } }] },
          { messagesAdded: [{ message: { id: 'social-1' } }] },
          { messagesAdded: [{ message: { id: 'updates-1' } }] },
          { messagesAdded: [{ message: { id: 'forums-1' } }] },
          { messagesAdded: [{ message: { id: 'principal-1' } }] },
        ],
      },
    });
    __get.mockImplementation(({ id }: { id: string }) => {
      const labelsByMessage: Record<string, string[]> = {
        'promo-1': ['CATEGORY_PROMOTIONS', 'UNREAD'],
        'social-1': ['CATEGORY_SOCIAL', 'UNREAD'],
        'updates-1': ['CATEGORY_UPDATES', 'UNREAD'],
        'forums-1': ['CATEGORY_FORUMS', 'UNREAD'],
        'principal-1': ['CATEGORY_PERSONAL', 'UNREAD', 'INBOX'],
      };
      return Promise.resolve({
        data: {
          labelIds: labelsByMessage[id],
          payload: { headers: [{ name: 'From', value: 'x@example.com' }, { name: 'Subject', value: 'Assunto' }] },
          snippet: 'trecho',
          internalDate: '1000',
        },
      });
    });

    const result = await buildClient().fetchIncremental('rt-123', 'h1');

    expect(result.emails.map((e) => e.gmailMessageId)).toEqual(['principal-1']);
  });

  it('fetchIncremental também descarta SPAM pelas labelIds', async () => {
    const { __historyList, __get } = mocks();
    __historyList.mockResolvedValue({
      data: { historyId: 'h2', history: [{ messagesAdded: [{ message: { id: 'spam-1' } }] }] },
    });
    __get.mockResolvedValue({
      data: {
        labelIds: ['SPAM'],
        payload: { headers: [] },
        snippet: '',
        internalDate: '1000',
      },
    });

    const result = await buildClient().fetchIncremental('rt-123', 'h1');

    expect(result.emails).toEqual([]);
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
            { mimeType: 'text/plain', body: { data: base64url('Olá, tudo bem?') } },
            { mimeType: 'text/html', body: { data: base64url('<p>Olá, tudo bem?</p>') } },
          ],
        },
        snippet: 'Olá, tudo...',
      },
    });

    const result = await buildClient().fetchFullBody('rt-123', 'msg-1');

    expect(result).toEqual({ texto: 'Olá, tudo bem?', ehPreview: false });
  });

  it('e-mail HTML-only (sem text/plain — a maioria dos e-mails reais): converte o HTML em texto '
    + 'legível, em vez de cair no snippet de ~200 caracteres', async () => {
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
    expect(result.texto).toContain('Sua fatura de R$ 150,00 vence amanhã. Categorias: A & B.');
    expect(result.texto).toContain('Item um');
    expect(result.texto).toContain('Item dois');
    expect(result.texto).toContain('Equipe Financeira');
    expect(result.ehPreview).toBe(false);
    // Estritamente mais informativo que o snippet que a UI mostrava antes.
    expect(result.texto.length).toBeGreaterThan('Olá Maria, Sua fatura de R$ 150,00 vence amanhã...'.length);
  });

  it('e-mail sem text/plain E sem text/html (ex.: só anexo): cai no snippet, mas marca ehPreview', async () => {
    const { __get } = mocks();
    __get.mockResolvedValue({
      data: {
        payload: { mimeType: 'application/pdf', body: { data: base64url('%PDF-binary-ish') } },
        snippet: 'Segue o anexo solicitado',
      },
    });

    const result = await buildClient().fetchFullBody('rt-123', 'msg-1');

    expect(result).toEqual({ texto: 'Segue o anexo solicitado', ehPreview: true });
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
              parts: [{ mimeType: 'text/html', body: { data: base64url('<div>Corpo aninhado</div>') } }],
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
