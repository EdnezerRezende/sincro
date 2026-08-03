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
}
