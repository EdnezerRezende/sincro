import { PasswordException, PDFParse } from 'pdf-parse';
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
          messages: { get, send, list, modify, trash, attachments: { get: attachmentsGet } },
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
  return jest.requireMock('googleapis') as {
    __get: jest.Mock;
    __send: jest.Mock;
    __list: jest.Mock;
    __modify: jest.Mock;
    __trash: jest.Mock;
    __getProfile: jest.Mock;
    __historyList: jest.Mock;
    __attachmentsGet: jest.Mock;
    __labelsList: jest.Mock;
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
    // Task 9: FetchedEmail carrega as labelIds da mensagem (não só serve para filtrar ruído).
    expect(result.emails[0].labelIds).toEqual(['CATEGORY_PERSONAL', 'UNREAD', 'INBOX']);
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

    const r = await clientComPayload(payload).fetchFullBodyComAnexos('rt', 'm1');

    expect(r.texto).toContain('Vencimento: 17/09\nValor total: 520,61');
    expect(r.anexos).toEqual([]);
    expect(r.ehPreview).toBe(false);
  });

  it('lists attachment metadata without downloading, including octet-stream .PDF', async () => {
    const payload = {
      mimeType: 'multipart/mixed',
      parts: [
        { mimeType: 'text/plain', body: { data: base64url('oi') } },
        { mimeType: 'application/octet-stream', filename: 'Fatura_082026.PDF', body: { attachmentId: 'att1', size: 12345 } },
        { mimeType: 'image/png', filename: 'logo.png', body: { attachmentId: 'att2', size: 10 } },
      ],
    };

    const r = await clientComPayload(payload).fetchFullBodyComAnexos('rt', 'm1');

    expect(r.anexos).toEqual([
      { filename: 'Fatura_082026.PDF', mimeType: 'application/octet-stream', size: 12345, attachmentId: 'att1' },
      { filename: 'logo.png', mimeType: 'image/png', size: 10, attachmentId: 'att2' },
    ]);
  });

  it('percorre multipart/mixed > multipart/related aninhado: imagem inline (sem filename, com Content-Id) fica de fora, PDF em outro nível entra', async () => {
    const payload = {
      mimeType: 'multipart/mixed',
      parts: [
        {
          mimeType: 'multipart/related',
          parts: [
            { mimeType: 'text/html', body: { data: base64url('<p>Corpo</p><img src="cid:logo">') } },
            {
              mimeType: 'image/png',
              filename: '',
              headers: [{ name: 'Content-ID', value: '<logo>' }],
              body: { attachmentId: 'inline-att', size: 500 },
            },
          ],
        },
        { mimeType: 'application/pdf', filename: 'fatura.pdf', body: { attachmentId: 'att-pdf', size: 999 } },
      ],
    };

    const r = await clientComPayload(payload).fetchFullBodyComAnexos('rt', 'm1');

    expect(r.anexos).toEqual([{ filename: 'fatura.pdf', mimeType: 'application/pdf', size: 999, attachmentId: 'att-pdf' }]);
  });

  it('anexo sem body.size vira size 0, em vez de undefined', async () => {
    const payload = {
      mimeType: 'multipart/mixed',
      parts: [
        { mimeType: 'text/plain', body: { data: base64url('oi') } },
        { mimeType: 'application/pdf', filename: 'sem-tamanho.pdf', body: { attachmentId: 'att-sem-size' } },
      ],
    };

    const r = await clientComPayload(payload).fetchFullBodyComAnexos('rt', 'm1');

    expect(r.anexos).toEqual([
      { filename: 'sem-tamanho.pdf', mimeType: 'application/pdf', size: 0, attachmentId: 'att-sem-size' },
    ]);
  });

  it('não converte texto plano genuíno mesmo com anexos presentes', async () => {
    const payload = {
      mimeType: 'multipart/mixed',
      parts: [
        { mimeType: 'text/plain', body: { data: base64url('Olá, segue sua fatura em anexo.') } },
        { mimeType: 'application/pdf', filename: 'fatura.pdf', body: { attachmentId: 'att1', size: 999 } },
      ],
    };

    const r = await clientComPayload(payload).fetchFullBodyComAnexos('rt', 'm1');

    expect(r.texto).toBe('Olá, segue sua fatura em anexo.');
    expect(r.ehPreview).toBe(false);
    expect(r.anexos).toEqual([{ filename: 'fatura.pdf', mimeType: 'application/pdf', size: 999, attachmentId: 'att1' }]);
  });
});

describe('GmailApiClient.fetchFullBody — wrapper fino sobre fetchFullBodyComAnexos', () => {
  it('devolve só { texto, ehPreview }, sem o campo anexos, mantendo o contrato antigo', async () => {
    const payload = {
      mimeType: 'multipart/mixed',
      parts: [
        { mimeType: 'text/plain', body: { data: base64url('Olá, tudo bem?') } },
        { mimeType: 'application/pdf', filename: 'fatura.pdf', body: { attachmentId: 'att1', size: 999 } },
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
  __attachmentsGet.mockReset().mockResolvedValue({ data: { data: dataBase64url } });
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

describe('GmailApiClient.fetchPdfAttachmentText', () => {
  const anexo = { filename: 'f.pdf', mimeType: 'application/pdf', size: PDF_MINIMO.length, attachmentId: 'att1' };

  it('extracts text from a PDF attachment', async () => {
    const client = clientComAttachment(PDF_MINIMO.toString('base64url'));

    await expect(client.fetchPdfAttachmentText('rt', 'm1', anexo)).resolves.toContain('Total da fatura');
  });

  it('returns null for an unreadable PDF', async () => {
    const client = clientComAttachment(Buffer.from('nao e pdf').toString('base64url'));

    await expect(client.fetchPdfAttachmentText('rt', 'm1', anexo)).resolves.toBeNull();
  });

  it('returns null when the PDF is password-protected (PasswordException)', async () => {
    const client = clientComAttachment(PDF_MINIMO.toString('base64url'));
    const getTextSpy = jest
      .spyOn(PDFParse.prototype, 'getText')
      .mockRejectedValueOnce(new PasswordException('senha necessária'));

    await expect(client.fetchPdfAttachmentText('rt', 'm1', anexo)).resolves.toBeNull();

    getTextSpy.mockRestore();
  });

  it('escolherPdf picks by mimeType or extension within size cap', () => {
    expect(
      GmailApiClient.escolherPdf([
        { filename: 'x.PDF', mimeType: 'application/octet-stream', size: 10, attachmentId: 'a' },
      ])?.attachmentId,
    ).toBe('a');
    expect(
      GmailApiClient.escolherPdf([
        { filename: 'big.pdf', mimeType: 'application/pdf', size: 6 * 1024 * 1024, attachmentId: 'b' },
      ]),
    ).toBeNull();
    expect(
      GmailApiClient.escolherPdf([{ filename: 'logo.png', mimeType: 'image/png', size: 1, attachmentId: 'c' }]),
    ).toBeNull();
  });

  it('propagates a gaxios error from attachments.get (classified by the caller)', async () => {
    const client = clientComAttachmentErro(
      Object.assign(new Error('boom'), { response: { status: 503 }, code: 503, config: {} }),
    );

    await expect(client.fetchPdfAttachmentText('rt', 'm1', anexo)).rejects.toBeDefined();
  });
});

/** Mocka `users.labels.list` (com `labels`, cada um `{ id, name }`) e `users.messages.list` (com
 *  `messages`, cada um `{ id }`) — usado pelos testes de `listarIdsComMarcador`. */
function clientComLabels(labels: { id: string; name: string }[], messages: { id: string }[]) {
  const { __labelsList, __list } = mocks();
  __labelsList.mockReset().mockResolvedValue({ data: { labels } });
  __list.mockReset().mockResolvedValue({ data: { messages } });
  return buildClient();
}

describe('GmailApiClient.listarIdsComMarcador', () => {
  it('resolves the label (NFC, case-insensitive) and lists message ids', async () => {
    const client = clientComLabels(
      [{ id: 'Label_7', name: 'sincro/finanças' }],
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

  it('returns an empty set without extra calls when the label does not exist', async () => {
    const client = clientComLabels([{ id: 'Label_1', name: 'Outro' }], []);

    await expect(client.listarIdsComMarcador('rt')).resolves.toEqual({ labelId: null, ids: new Set() });
    expect(mocks().__list).not.toHaveBeenCalled();
  });
});
