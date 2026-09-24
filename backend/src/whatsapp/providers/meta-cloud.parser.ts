import { Injectable } from '@nestjs/common';
import * as crypto from 'crypto';

@Injectable()
export class MetaCloudParser {
  /**
   * Valida a assinatura HMAC-SHA256 do webhook da Meta.
   * Header deve vir como "sha256=<hex>", remove prefixo e compara em tempo constante.
   */
  validateSignature(
    headerValue: string | undefined,
    rawBody: Buffer,
    appSecret: string,
  ): boolean {
    if (!headerValue) return false;

    const [algorithm, hashHex] = headerValue.split('=');
    if (algorithm !== 'sha256' || !hashHex) return false;

    const expectedHash = crypto
      .createHmac('sha256', appSecret)
      .update(rawBody)
      .digest('hex');

    const headerBuffer = Buffer.from(hashHex, 'hex');
    const expectedBuffer = Buffer.from(expectedHash, 'hex');

    if (headerBuffer.length !== expectedBuffer.length) return false;
    return crypto.timingSafeEqual(headerBuffer, expectedBuffer);
  }

  /**
   * Parse webhook payload da Meta.
   * Retorna array de mensagens (filtra só messages[]) ou null se inválido.
   */
  parseWebhook(body: any): WebhookMessage[] {
    const messages: WebhookMessage[] = [];

    try {
      if (!Array.isArray(body?.entry)) return messages;

      for (const entry of body.entry) {
        if (!Array.isArray(entry?.changes)) continue;

        for (const change of entry.changes) {
          const value = change?.value;
          if (!value || value.messaging_product !== 'whatsapp') continue;

          // Processa só messages[]; ignora statuses[], errors[], etc.
          if (Array.isArray(value.messages)) {
            for (const msg of value.messages) {
              const phoneNumberId = value?.metadata?.phone_number_id;
              const from = msg?.from; // sempre presente em messages[]

              messages.push({
                wamid: msg.id,
                from,
                timestamp: msg.timestamp,
                type: this.mapMessageType(msg),
                content: msg,
                phoneNumberId,
              });
            }
          }
        }
      }
    } catch (e) {
      // Payload malformado: retorna array vazio, não tira exceção
    }

    return messages;
  }

  private mapMessageType(msg: any): string {
    if (msg.type === 'text') return 'text';
    if (msg.type === 'interactive') {
      if (msg.interactive?.type === 'button_reply') return 'interactive';
      if (msg.interactive?.type === 'list_reply') return 'interactive';
      return 'interactive';
    }
    if (msg.type === 'audio') return 'audio';
    if (msg.type === 'image') return 'image';
    if (['sticker', 'location', 'document', 'contacts', 'reaction', 'video', 'system', 'button', 'order'].includes(msg.type))
      return 'outro';
    if (msg.type === 'unsupported') return 'outro';
    return 'outro';
  }
}

export interface WebhookMessage {
  wamid: string;
  from: string;
  timestamp: string;
  type: string;
  content: any;
  phoneNumberId?: string;
}
