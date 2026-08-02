import { LlmEmailClassifier } from './llm-email-classifier.service';

function buildFakeAnthropicClient(responseText: string) {
  return {
    messages: {
      create: jest.fn().mockResolvedValue({
        content: [{ type: 'text', text: responseText }],
      }),
    },
  };
}

describe('LlmEmailClassifier', () => {
  it('parses the JSON response into a classification', async () => {
    const fakeClient = buildFakeAnthropicClient('{"categoria":"PRECISA_ATENCAO","resumoCurto":"Fatura vence amanhã"}');
    const classifier = new LlmEmailClassifier(fakeClient as any);

    const result = await classifier.classify(
      { remetente: 'banco@example.com', assunto: 'Fatura', corpo: 'Vence amanhã.' },
      { tomPreferido: 'DIRETO_E_CURTO' },
    );

    expect(result).toEqual({ categoria: 'PRECISA_ATENCAO', resumoCurto: 'Fatura vence amanhã' });
    expect(fakeClient.messages.create).toHaveBeenCalledWith(
      expect.objectContaining({
        messages: [expect.objectContaining({ content: expect.stringContaining('Fatura') })],
      }),
    );
  });

  it('falls back to PODE_ESPERAR with the subject as the summary when the model response is not valid JSON', async () => {
    const fakeClient = buildFakeAnthropicClient('não é json');
    const classifier = new LlmEmailClassifier(fakeClient as any);

    const result = await classifier.classify(
      { remetente: 'x@example.com', assunto: 'Assunto original', corpo: '' },
      {},
    );

    expect(result).toEqual({ categoria: 'PODE_ESPERAR', resumoCurto: 'Assunto original' });
  });

  it('falls back to PODE_ESPERAR when the API call itself throws', async () => {
    const fakeClient = { messages: { create: jest.fn().mockRejectedValue(new Error('network error')) } };
    const classifier = new LlmEmailClassifier(fakeClient as any);

    const result = await classifier.classify({ remetente: 'x@example.com', assunto: 'Assunto', corpo: '' }, {});

    expect(result).toEqual({ categoria: 'PODE_ESPERAR', resumoCurto: 'Assunto' });
  });
});
