import { createHmac } from 'crypto';
import { UnauthorizedException } from '@nestjs/common';
import { FinanceWebhookController } from './finance-webhook.controller';

function buildDeps() {
  const prisma = { financeConnection: { findFirst: jest.fn() } };
  const financeSyncService = { syncConnection: jest.fn().mockResolvedValue(undefined) };
  return { prisma, financeSyncService };
}

function sign(body: string, secret: string): string {
  return createHmac('sha256', secret).update(body).digest('hex');
}

describe('FinanceWebhookController', () => {
  const originalEnv = { ...process.env };

  beforeEach(() => {
    process.env.PLUGGY_WEBHOOK_SECRET = 'test-secret';
  });

  afterEach(() => {
    process.env = { ...originalEnv };
  });

  it('syncs the matching connection when the signature is valid', async () => {
    const { prisma, financeSyncService } = buildDeps();
    prisma.financeConnection.findFirst.mockResolvedValue({ id: 'conn-1' });
    const controller = new FinanceWebhookController(prisma as any, financeSyncService as any);
    const payload = { event: 'item/updated', itemId: 'item-1' };
    const rawBody = Buffer.from(JSON.stringify(payload));
    const signature = sign(rawBody.toString(), 'test-secret');

    const result = await controller.handleWebhook(payload, signature, { rawBody } as any);

    expect(financeSyncService.syncConnection).toHaveBeenCalledWith('conn-1');
    expect(result).toEqual({ received: true });
  });

  it('acknowledges without syncing when the itemId is unknown', async () => {
    const { prisma, financeSyncService } = buildDeps();
    prisma.financeConnection.findFirst.mockResolvedValue(null);
    const controller = new FinanceWebhookController(prisma as any, financeSyncService as any);
    const payload = { event: 'item/updated', itemId: 'unknown-item' };
    const rawBody = Buffer.from(JSON.stringify(payload));
    const signature = sign(rawBody.toString(), 'test-secret');

    const result = await controller.handleWebhook(payload, signature, { rawBody } as any);

    expect(financeSyncService.syncConnection).not.toHaveBeenCalled();
    expect(result).toEqual({ received: true });
  });

  it('rejects a request with an invalid signature', async () => {
    const { prisma, financeSyncService } = buildDeps();
    const controller = new FinanceWebhookController(prisma as any, financeSyncService as any);
    const payload = { event: 'item/updated', itemId: 'item-1' };
    const rawBody = Buffer.from(JSON.stringify(payload));

    await expect(
      controller.handleWebhook(payload, 'not-the-right-signature-not-the-right-signature', { rawBody } as any),
    ).rejects.toThrow(UnauthorizedException);
    expect(financeSyncService.syncConnection).not.toHaveBeenCalled();
  });

  it('rejects a request with no signature header', async () => {
    const { prisma, financeSyncService } = buildDeps();
    const controller = new FinanceWebhookController(prisma as any, financeSyncService as any);
    const payload = { event: 'item/updated', itemId: 'item-1' };
    const rawBody = Buffer.from(JSON.stringify(payload));

    await expect(controller.handleWebhook(payload, undefined, { rawBody } as any)).rejects.toThrow(UnauthorizedException);
  });
});
