import { Injectable } from '@nestjs/common';
import { google, gmail_v1 } from 'googleapis';
import { decode as decodeHtmlEntities } from 'html-entities';
import { GmailOAuthService } from './gmail-oauth.service';

export interface FetchedEmail {
  gmailMessageId: string;
  remetente: string;
  assunto: string;
  corpo: string;
  recebidoEm: Date;
}

/** Categorias/labels do Gmail que não são a caixa "Principal". `fetchInitialUnread` já exclui a
 *  maior parte disso na própria busca (`-category:promotions` etc. no `q`, ver o comentário lá),
 *  mas esta lista continua sendo aplicada nos DOIS caminhos de sincronização, depois da busca:
 *  1. `fetchIncremental` usa `history.list`, que não aceita `q` — ali este é o ÚNICO filtro
 *     possível, aplicado olhando as `labelIds` de cada mensagem já buscada (ver `fetchMessages`).
 *  2. `fetchInitialUnread` também passa por aqui como segunda camada de defesa: a documentação
 *     oficial do Gmail não garante que `-category:promotions` etc. excluam mensagens quando o
 *     usuário desligou as abas da caixa de entrada (as categorias continuam existindo como labels
 *     internos mesmo com as abas ocultas, mas isso não é documentado explicitamente) — então, se a
 *     exclusão no `q` falhar por algum motivo, este segundo filtro ainda descarta pelo label.
 *  SPAM já fica de fora por padrão em ambos os caminhos (`includeSpamTrash` nunca é setado como
 *  `true`), mas é listado aqui também como terceira camada de defesa caso apareça em algum retorno
 *  inesperado. */
const NOISE_LABELS = new Set([
  'CATEGORY_PROMOTIONS',
  'CATEGORY_SOCIAL',
  'CATEGORY_UPDATES',
  'CATEGORY_FORUMS',
  'SPAM',
]);

@Injectable()
export class GmailApiClient {
  constructor(private readonly oauthService: GmailOAuthService) {}

  private gmailFor(refreshToken: string): gmail_v1.Gmail {
    const auth = this.oauthService.authenticatedClientFor(refreshToken);
    return google.gmail({ version: 'v1', auth });
  }

  /** First sync for a newly connected account: unread messages from the last 7 days, capped at 50.
   *
   *  Uses `in:inbox` (not `category:primary`) as the base filter: `category:primary` depends on
   *  the user having Gmail's tabbed inbox enabled — someone who turned tabs off gets an EMPTY
   *  "Principal" category and this search would silently return nothing, even though their inbox
   *  is full of unread mail. `in:inbox` matches regardless of tab configuration.
   *
   *  The Promoções/Social/Atualizações/Fóruns noise ALSO has to be excluded right here, in the
   *  `q` sent to `messages.list`, not only afterwards in `fetchMessages` — `maxResults: 50` is
   *  applied by Gmail's API before any filtering this app does. If the account has 50+ unread
   *  promotional e-mails, `messages.list` returns those 50 promos, `fetchMessages` discards every
   *  one of them by label, and the user gets back an EMPTY inbox on first sync despite having real
   *  unread mail. Excluding `-category:promotions -category:social -category:updates
   *  -category:forums` in the query itself means the 50-message cap is spent on messages that can
   *  actually survive the label filter. `fetchMessages` still re-checks `labelIds` below as a
   *  second barrier (see `NOISE_LABELS` above) in case the negative `category:` filter doesn't
   *  fully apply when the user has the tabbed inbox turned off — the Gmail search-operator
   *  documentation doesn't explicitly guarantee that behavior, so the label check stays as a
   *  safety net instead of being trusted alone. */
  async fetchInitialUnread(refreshToken: string): Promise<{ emails: FetchedEmail[]; historyId: string | null }> {
    const gmail = this.gmailFor(refreshToken);
    const sevenDaysAgoUnixSeconds = Math.floor((Date.now() - 7 * 24 * 60 * 60 * 1000) / 1000);
    const list = await gmail.users.messages.list({
      userId: 'me',
      q: `is:unread after:${sevenDaysAgoUnixSeconds} in:inbox -category:promotions -category:social -category:updates -category:forums`,
      maxResults: 50,
    });
    const messageIds = (list.data.messages ?? [])
      .map((m) => m.id)
      .filter((id): id is string => typeof id === 'string');
    const emails = await this.fetchMessages(gmail, messageIds);
    const profile = await gmail.users.getProfile({ userId: 'me' });
    return { emails, historyId: profile.data.historyId ?? null };
  }

  /** Incremental sync using a previously stored historyId. `history.list` has no `q` parameter, so
   *  the Promoções/Social/Atualizações/Fóruns filter is applied here by `fetchMessages`, which
   *  discards a message by its `labelIds` right after fetching it — before classification or
   *  persistence ever see it. `fetchInitialUnread` above uses the very same blacklist, so both
   *  sync paths agree regardless of whether the user has Gmail's tabbed inbox on or off. */
  async fetchIncremental(
    refreshToken: string,
    sinceHistoryId: string,
  ): Promise<{ emails: FetchedEmail[]; historyId: string | null; historyExpired: boolean }> {
    const gmail = this.gmailFor(refreshToken);
    try {
      const history = await gmail.users.history.list({
        userId: 'me',
        startHistoryId: sinceHistoryId,
        historyTypes: ['messageAdded'],
      });
      const messageIds = new Set<string>();
      for (const record of history.data.history ?? []) {
        for (const added of record.messagesAdded ?? []) {
          if (added.message?.id) messageIds.add(added.message.id);
        }
      }
      const emails = await this.fetchMessages(gmail, Array.from(messageIds));
      return { emails, historyId: history.data.historyId ?? sinceHistoryId, historyExpired: false };
    } catch (error: unknown) {
      // Gmail returns 404 when the stored historyId is too old (beyond Gmail's retention window).
      const status = (error as { code?: number })?.code;
      if (status === 404) {
        return { emails: [], historyId: null, historyExpired: true };
      }
      throw error;
    }
  }

  private async fetchMessages(gmail: gmail_v1.Gmail, ids: string[]): Promise<FetchedEmail[]> {
    const emails: FetchedEmail[] = [];
    for (const id of ids) {
      const message = await gmail.users.messages.get({
        userId: 'me',
        id,
        format: 'metadata',
        metadataHeaders: ['From', 'Subject'],
      });
      // Discard Promoções/Social/Atualizações/Fóruns/Spam by label. Both `fetchInitialUnread` and
      // `fetchIncremental` funnel through here, so the same blacklist applies to both sync paths.
      const labelIds = message.data.labelIds ?? [];
      if (labelIds.some((label) => NOISE_LABELS.has(label))) continue;
      const headers = message.data.payload?.headers ?? [];
      const getHeader = (name: string) => headers.find((h) => h.name === name)?.value ?? '';
      emails.push({
        gmailMessageId: id,
        remetente: getHeader('From'),
        assunto: getHeader('Subject'),
        corpo: message.data.snippet ?? '',
        recebidoEm: new Date(Number(message.data.internalDate ?? Date.now())),
      });
    }
    return emails;
  }

  /** Removes the message from the inbox WITHOUT deleting it: only the `INBOX` label is dropped, so
   *  it stays fully intact in "Todos os e-mails"/search — fully reversible from Gmail itself. */
  async arquivar(refreshToken: string, gmailMessageId: string): Promise<void> {
    const gmail = this.gmailFor(refreshToken);
    await gmail.users.messages.modify({
      userId: 'me',
      id: gmailMessageId,
      requestBody: { removeLabelIds: ['INBOX'] },
    });
  }

  /** Moves the message to Trash (`messages.trash`) — recoverable there for ~30 days, unlike
   *  `messages.delete`, which is permanent and is intentionally never called by this app. */
  async excluir(refreshToken: string, gmailMessageId: string): Promise<void> {
    const gmail = this.gmailFor(refreshToken);
    await gmail.users.messages.trash({ userId: 'me', id: gmailMessageId });
  }

  /** Full readable body for reading the e-mail / drafting a reply — `fetchInitialUnread`/
   *  `fetchIncremental` above only ever read the short `snippet` via `format: 'metadata'`;
   *  generating a coherent draft (or showing the actual message, not a ~200-character stub) needs
   *  the real text.
   *
   *  Prefers a `text/plain` MIME part when the message has one. Most real-world e-mail (marketing,
   *  receipts, most personal mail sent from a webmail client) has NO `text/plain` part at all —
   *  only `text/html` — so falling back straight to `snippet` for those, as this used to do, meant
   *  the majority of e-mails were silently truncated to ~200 characters with no indication anything
   *  was missing. When only HTML is available, it's converted to plain text (see
   *  `htmlParaTextoLegivel`) instead of being dumped raw on screen or discarded. Only when NEITHER
   *  part exists does this fall back to Gmail's own `snippet` — `ehPreview: true` tells callers
   *  that what they got is a short preview, not the full message, so the UI can say so instead of
   *  presenting it as complete. */
  async fetchFullBody(
    refreshToken: string,
    gmailMessageId: string,
  ): Promise<{ texto: string; ehPreview: boolean }> {
    const gmail = this.gmailFor(refreshToken);
    const message = await gmail.users.messages.get({ userId: 'me', id: gmailMessageId, format: 'full' });

    const textoPlano = this.extractPlainTextBody(message.data.payload);
    if (textoPlano !== null && textoPlano.trim() !== '') {
      return { texto: textoPlano, ehPreview: false };
    }

    const html = this.extractHtmlBody(message.data.payload);
    if (html !== null) {
      const textoConvertido = GmailApiClient.htmlParaTextoLegivel(html);
      if (textoConvertido !== '') {
        return { texto: textoConvertido, ehPreview: false };
      }
    }

    return { texto: message.data.snippet ?? '', ehPreview: true };
  }

  private extractPlainTextBody(payload: gmail_v1.Schema$MessagePart | undefined): string | null {
    if (!payload) return null;
    if (payload.mimeType === 'text/plain' && payload.body?.data) {
      return Buffer.from(payload.body.data, 'base64url').toString('utf8');
    }
    for (const part of payload.parts ?? []) {
      const found = this.extractPlainTextBody(part);
      if (found) return found;
    }
    return null;
  }

  /** Same traversal as `extractPlainTextBody`, looking for `text/html` instead — this is the part
   *  that exists on most real-world e-mail when `text/plain` doesn't. */
  private extractHtmlBody(payload: gmail_v1.Schema$MessagePart | undefined): string | null {
    if (!payload) return null;
    if (payload.mimeType === 'text/html' && payload.body?.data) {
      return Buffer.from(payload.body.data, 'base64url').toString('utf8');
    }
    for (const part of payload.parts ?? []) {
      const found = this.extractHtmlBody(part);
      if (found) return found;
    }
    return null;
  }

  /** Converts raw e-mail HTML into readable plain text. Not a full HTML/CSS engine — that would be
   *  overkill for text that ends up flattened into a scrollable text view — but deliberately more
   *  careful than a bare `.replace(/<[^>]+>/g, '')`, which was tried first and left the screen full
   *  of literal `&nbsp;`/`&amp;` and paragraphs jammed into one unreadable run:
   *   1. Drops `<script>`/`<style>` bodies entirely — never meant to be read.
   *   2. Turns block-level boundaries (`<br>`, `</p>`, `</div>`, `</tr>`, `<li>`, headings) into
   *      line breaks BEFORE any tag is stripped, so structure survives as line breaks instead of
   *      vanishing.
   *   3. Strips whatever tags remain.
   *   4. Decodes HTML entities via the `html-entities` package (already a transitive dependency
   *      of `firebase-admin`/`@google-cloud/storage`, now declared directly) instead of a hand-rolled
   *      lookup table. This app is in Portuguese, so a table would need every accented named entity
   *      (`&aacute;`, `&ccedil;`, `&atilde;`, `&otilde;`, `&Ccedil;`, …) plus punctuation/symbol
   *      entities (`&ordm;`, `&euro;`, `&bull;`, `&laquo;`, `&copy;`, …) and would silently miss the
   *      next one that shows up in real mail. `html-entities` decodes the full HTML5 named-entity
   *      table (~2200 entries, covers every accented Portuguese letter) plus numeric/hex entities
   *      (`&#233;`/`&#xe9;`), so nothing needs to be hand-curated.
   *   5. Collapses the resulting whitespace: trims each line, collapses runs of blank lines. `&nbsp;`
   *      decodes to U+00A0 (non-breaking space, not a plain space), so it's normalized to a regular
   *      space first — otherwise it would survive the whitespace-collapsing step untouched. */
  private static htmlParaTextoLegivel(html: string): string {
    let texto = html
      .replace(/<script[\s\S]*?<\/script>/gi, '')
      .replace(/<style[\s\S]*?<\/style>/gi, '')
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<\/(p|div|tr|h[1-6])>/gi, '\n')
      .replace(/<li[^>]*>/gi, '\n• ')
      .replace(/<\/li>/gi, '')
      .replace(/<\/(td|th)>/gi, '\t')
      .replace(/<[^>]+>/g, '');

    texto = GmailApiClient.decodificarEntidadesHtml(texto);

    return texto
      .split('\n')
      .map((linha) => linha.replace(/[ \t]+/g, ' ').trim())
      .join('\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
  }

  /** Delegates to `html-entities`, which covers the full HTML5 named-entity table (all accented
   *  Portuguese letters included) plus numeric/hex entities — see the class doc on
   *  `htmlParaTextoLegivel` above for why a hand-rolled table was replaced with this. */
  private static decodificarEntidadesHtml(texto: string): string {
    return decodeHtmlEntities(texto).replace(/ /g, ' ');
  }

  /** Valores de cabeçalho vêm de um e-mail RECEBIDO (remetente/assunto persistidos como o Gmail os
   *  entregou), não de algo digitado pelo usuário. Um CR/LF cru vindo de um e-mail hostil quebraria
   *  a linha do cabeçalho e injetaria cabeçalhos arbitrários (um `Bcc:` escondido, por exemplo) na
   *  mensagem enviada da conta do PRÓPRIO usuário. */
  private static sanitizarValorDeCabecalho(valor: string): string {
    return valor.replace(/[\r\n]+/g, ' ').trim();
  }

  /** Cabeçalhos MIME só admitem US-ASCII. Este app é em português — "Reunião"/"Confirmação" são o
   *  caso comum —, então qualquer caractere fora do ASCII imprimível vira encoded-word RFC 2047.
   *  O texto é fatiado para nenhum encoded-word passar de 75 caracteres (RFC 2047 §2), com as
   *  partes dobradas em linhas de continuação (CRLF + espaço). */
  private static codificarCabecalhoRfc2047(valor: string): string {
    if (/^[\x20-\x7E]*$/.test(valor)) return valor;
    const MAX_BYTES_POR_PALAVRA = 45; // base64(45 bytes) = 60 chars; + "=?UTF-8?B?" e "?=" = 72
    const bytes = Buffer.from(valor, 'utf8');
    const palavras: string[] = [];
    let inicio = 0;
    while (inicio < bytes.length) {
      let fim = Math.min(inicio + MAX_BYTES_POR_PALAVRA, bytes.length);
      // Nunca cortar no meio de uma sequência UTF-8 multibyte.
      while (fim < bytes.length && (bytes[fim] & 0xc0) === 0x80) fim--;
      palavras.push(`=?UTF-8?B?${bytes.subarray(inicio, fim).toString('base64')}?=`);
      inicio = fim;
    }
    return palavras.join('\r\n ');
  }

  /** `To:` não é texto livre como `Subject:` — é `display-name <addr-spec>` (RFC 5322 §3.4).
   *  Um encoded-word RFC 2047 não pode conter `<`, `>` ou `@`, então codificar a string inteira
   *  destruiria o endereço dentro do blob base64. Codifica só o nome de exibição e deixa o
   *  `<endereco>` intacto. */
  private static codificarEnderecoPara(valor: string): string {
    const match = valor.match(/^(.*)(<[^<>]+>)\s*$/);
    if (!match) return GmailApiClient.codificarCabecalhoRfc2047(valor);
    const [, nome, endereco] = match;
    const nomeTrim = nome.trim();
    if (!nomeTrim) return endereco;
    return `${GmailApiClient.codificarCabecalhoRfc2047(nomeTrim)} ${endereco}`;
  }

  /** Sends a real reply in the original thread. `params.para` is the original `remetente` field
   *  verbatim (e.g. `"Carlos <carlos@example.com>"`) — valid directly as a `To:` header per
   *  RFC 5322, no parsing needed. */
  async sendReply(
    refreshToken: string,
    params: { gmailMessageId: string; para: string; assunto: string; texto: string },
  ): Promise<void> {
    const gmail = this.gmailFor(refreshToken);
    const original = await gmail.users.messages.get({
      userId: 'me',
      id: params.gmailMessageId,
      format: 'metadata',
      metadataHeaders: ['Message-Id', 'References'],
    });
    const headers = original.data.payload?.headers ?? [];
    const sanitizar = GmailApiClient.sanitizarValorDeCabecalho;
    const messageIdHeader = sanitizar(headers.find((h) => h.name === 'Message-Id')?.value ?? '');
    const referencesHeader = sanitizar(headers.find((h) => h.name === 'References')?.value ?? '');
    const references = [referencesHeader, messageIdHeader].filter(Boolean).join(' ');
    const para = GmailApiClient.codificarEnderecoPara(sanitizar(params.para));
    const assunto = GmailApiClient.codificarCabecalhoRfc2047(`Re: ${sanitizar(params.assunto)}`);

    // Só os CABEÇALHOS são higienizados/codificados; `params.texto` — exatamente o que o usuário
    // leu e editou na tela — vai para o corpo byte a byte, sem nenhum pós-processamento.
    const raw = [
      'MIME-Version: 1.0',
      `To: ${para}`,
      `Subject: ${assunto}`,
      `In-Reply-To: ${messageIdHeader}`,
      `References: ${references}`,
      'Content-Type: text/plain; charset="UTF-8"',
      '',
      params.texto,
    ].join('\r\n');
    const encoded = Buffer.from(raw, 'utf8').toString('base64url');

    await gmail.users.messages.send({
      userId: 'me',
      requestBody: { raw: encoded, threadId: original.data.threadId ?? undefined },
    });
  }
}
