import {
  Controller,
  Get,
  Post,
  Query,
  Body,
  Req,
  HttpException,
  HttpStatus,
  BadRequestException,
  ForbiddenException,
  Logger,
} from '@nestjs/common';
import type { Request } from 'express';
import { PrismaService } from '../prisma/prisma.service';
import { MetaCloudParser } from './providers/meta-cloud.parser';
import { EventEmitter2 } from '@nestjs/event-emitter';

@Controller('whatsapp')
export class WhatsappWebhookController {
  private readonly logger = new Logger(WhatsappWebhookController.name);

  constructor(
    private prisma: PrismaService,
    private parser: MetaCloudParser,
    private eventEmitter: EventEmitter2,
  ) {}

  /**
   * GET /whatsapp/webhook
   * Verifica a assinatura na conexão inicial do webhook.
   */
  @Get('webhook')
  webhookVerify(
    @Query('hub.mode') mode: string,
    @Query('hub.challenge') challenge: string,
    @Query('hub.verify_token') token: string,
  ) {
    const verifyToken = process.env.WHATSAPP_VERIFY_TOKEN;
    if (!verifyToken) {
      throw new HttpException('Webhook não configurado', HttpStatus.SERVICE_UNAVAILABLE);
    }

    if (mode === 'subscribe' && token === verifyToken) {
      // Meta espera a challenge como texto puro (não JSON)
      return challenge;
    }

    throw new ForbiddenException();
  }

  /**
   * POST /whatsapp/webhook
   * Recebe e processa mensagens da Meta.
   * Validação de assinatura → gravação imediata → 200 → processamento assíncrono.
   */
  @Post('webhook')
  async webhookReceive(@Req() req: Request, @Body() body: any) {
    const appSecret = process.env.WHATSAPP_APP_SECRET;
    const verifyToken = process.env.WHATSAPP_VERIFY_TOKEN;

    if (!appSecret || !verifyToken) {
      this.logger.error('Webhook: variáveis de ambiente não configuradas');
      throw new HttpException('Webhook não configurado', HttpStatus.SERVICE_UNAVAILABLE);
    }

    // 1. Validar assinatura
    const signatureHeader = req.headers['x-hub-signature-256'] as string;
    const rawBody = (req as any).rawBody || Buffer.from(JSON.stringify(body));

    if (!this.parser.validateSignature(signatureHeader, rawBody, appSecret)) {
      this.logger.warn('Webhook: assinatura inválida');
      throw new ForbiddenException();
    }

    // 2. Parse mensagens
    const messages = this.parser.parseWebhook(body);
    if (messages.length === 0) {
      // Webhook válido mas sem messages (ex: status updates, errors, outros fields)
      return { status: 'ok' };
    }

    // 3. Gravar cada mensagem como RECEBIDA (idempotente por wamid)
    const wamidHashes: string[] = [];
    for (const msg of messages) {
      const wamidHash = this.hashWamid(msg.wamid);
      try {
        await this.prisma.whatsappMensagem.upsert({
          where: { wamid: wamidHash },
          update: {}, // Se já existe (reentrega), não toca
          create: {
            wamid: wamidHash,
            telefoneHash: this.hashTelefone(msg.from),
            direcao: 'ENTRADA',
            tipo: msg.type,
            textoCifrado: null, // Será preenchido durante processamento
            status: 'RECEBIDA',
            criadoEm: new Date(parseInt(msg.timestamp) * 1000),
          },
        });
        wamidHashes.push(wamidHash);
      } catch (e) {
        if (e.code === 'P2002') {
          // Reentrega: wamid já existe, ignora
          this.logger.debug(`Webhook: reentrega detectada (wamid ${msg.wamid})`);
          continue;
        }
        this.logger.error(`Webhook: erro ao gravar mensagem`, e);
      }
    }

    // 4. Emitir evento para processamento assíncrono (§6.5)
    for (const wamidHash of wamidHashes) {
      this.eventEmitter.emit('whatsapp.mensagem.recebida', { wamidHash });
    }

    // 5. Responder 200 imediatamente (antes de qualquer efeito externo)
    return { status: 'ok' };
  }

  private hashWamid(wamid: string): string {
    const pepper = process.env.WHATSAPP_HASH_PEPPER || '';
    return this.hmacSha256(pepper, wamid);
  }

  private hashTelefone(telefone: string): string {
    const pepper = process.env.WHATSAPP_HASH_PEPPER || '';
    return this.hmacSha256(pepper, telefone);
  }

  private hmacSha256(key: string, message: string): string {
    return require('crypto')
      .createHmac('sha256', key)
      .update(message)
      .digest('hex');
  }
}
