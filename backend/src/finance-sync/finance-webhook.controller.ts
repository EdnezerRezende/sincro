import { Body, Controller, Headers, Post, Req, UnauthorizedException } from '@nestjs/common';
import type { RawBodyRequest } from '@nestjs/common';
import type { Request } from 'express';
import { createHmac, timingSafeEqual } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { FinanceSyncService } from './finance-sync.service';

// Plain interface, not a class-validator DTO: the global ValidationPipe (whitelist: true,
// forbidNonWhitelisted: true) would reject any field Pluggy sends beyond what we declare, and
// Pluggy's webhook payload carries more fields than we use. An interface erases to `Object` at
// runtime, which the ValidationPipe skips entirely — see main.ts's `toValidate` behavior.
interface PluggyWebhookPayload {
  event: string;
  itemId: string;
}

@Controller('financas/webhooks')
export class FinanceWebhookController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly financeSyncService: FinanceSyncService,
  ) {}

  @Post('pluggy')
  async handleWebhook(
    @Body() payload: PluggyWebhookPayload,
    @Headers('x-pluggy-signature') signature: string | undefined,
    @Req() req: RawBodyRequest<Request>,
  ) {
    this.verifySignature(req.rawBody, signature);

    const connection = await this.prisma.financeConnection.findFirst({ where: { pluggyItemId: payload.itemId } });
    if (connection) {
      await this.financeSyncService.syncConnection(connection.id);
    }
    return { received: true };
  }

  private verifySignature(rawBody: Buffer | undefined, signature: string | undefined): void {
    const secret = process.env.PLUGGY_WEBHOOK_SECRET;
    if (!secret) throw new Error('PLUGGY_WEBHOOK_SECRET não configurado.');
    if (!signature || !rawBody) {
      throw new UnauthorizedException('Assinatura do webhook ausente.');
    }
    // Signed over the raw request bytes, not JSON.stringify(payload) — re-serializing the
    // already-parsed body can differ byte-for-byte from what Pluggy actually signed (key
    // ordering, whitespace), which would make every real webhook fail verification.
    const expected = createHmac('sha256', secret).update(rawBody).digest('hex');
    const signatureBuffer = Buffer.from(signature, 'hex');
    const expectedBuffer = Buffer.from(expected, 'hex');
    if (signatureBuffer.length !== expectedBuffer.length || !timingSafeEqual(signatureBuffer, expectedBuffer)) {
      throw new UnauthorizedException('Assinatura do webhook inválida.');
    }
  }
}
