import { EmailDraftService } from './email-draft.service';

describe('EmailDraftService', () => {
  it('returns the three tone variants parsed from the LLM response', async () => {
    const fakeClient = {
      messages: {
        create: jest.fn().mockResolvedValue({
          content: [
            {
              type: 'text',
              text: JSON.stringify({
                direto: 'Envio até amanhã.',
                formal: 'Prezado, informo que enviarei até amanhã.',
                padrao: 'Envio até amanhã, tudo bem?',
              }),
            },
          ],
        }),
      },
    } as any;
    const service = new EmailDraftService(fakeClient);

    const result = await service.gerar({ remetente: 'Carlos', assunto: 'Prazo', corpo: 'Qual o prazo?' });

    expect(result).toEqual({
      direto: 'Envio até amanhã.',
      formal: 'Prezado, informo que enviarei até amanhã.',
      padrao: 'Envio até amanhã, tudo bem?',
    });
  });

  it('propagates a parse failure instead of silently returning empty drafts', async () => {
    const fakeClient = {
      messages: {
        create: jest.fn().mockResolvedValue({ content: [{ type: 'text', text: 'not json' }] }),
      },
    } as any;
    const service = new EmailDraftService(fakeClient);

    await expect(
      service.gerar({ remetente: 'Carlos', assunto: 'Prazo', corpo: 'Qual o prazo?' }),
    ).rejects.toThrow();
  });
});
