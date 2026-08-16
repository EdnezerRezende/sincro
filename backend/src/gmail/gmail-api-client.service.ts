import { Injectable } from '@nestjs/common';
import { google, gmail_v1 } from 'googleapis';
import { GmailOAuthService } from './gmail-oauth.service';

export interface FetchedEmail {
  gmailMessageId: string;
  remetente: string;
  assunto: string;
  corpo: string;
  recebidoEm: Date;
}

@Injectable()
export class GmailApiClient {
  constructor(private readonly oauthService: GmailOAuthService) {}

  private gmailFor(refreshToken: string): gmail_v1.Gmail {
    const auth = this.oauthService.authenticatedClientFor(refreshToken);
    return google.gmail({ version: 'v1', auth });
  }

  /** First sync for a newly connected account: unread messages from the last 7 days, capped at 50. */
  async fetchInitialUnread(refreshToken: string): Promise<{ emails: FetchedEmail[]; historyId: string | null }> {
    const gmail = this.gmailFor(refreshToken);
    const sevenDaysAgoUnixSeconds = Math.floor((Date.now() - 7 * 24 * 60 * 60 * 1000) / 1000);
    const list = await gmail.users.messages.list({
      userId: 'me',
      q: `is:unread after:${sevenDaysAgoUnixSeconds}`,
      maxResults: 50,
    });
    const messageIds = (list.data.messages ?? []).map((m) => m.id!);
    const emails = await this.fetchMessages(gmail, messageIds);
    const profile = await gmail.users.getProfile({ userId: 'me' });
    return { emails, historyId: profile.data.historyId ?? null };
  }

  /** Incremental sync using a previously stored historyId. */
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

  /** Full plain-text body for drafting a reply — `fetchInitialUnread`/`fetchIncremental` above
   *  only ever read the short `snippet` via `format: 'metadata'`; generating a coherent draft
   *  needs the real text. */
  async fetchFullBody(refreshToken: string, gmailMessageId: string): Promise<string> {
    const gmail = this.gmailFor(refreshToken);
    const message = await gmail.users.messages.get({ userId: 'me', id: gmailMessageId, format: 'full' });
    return this.extractPlainTextBody(message.data.payload) ?? message.data.snippet ?? '';
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
