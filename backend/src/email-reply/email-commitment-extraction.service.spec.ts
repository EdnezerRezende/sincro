import { EmailCommitmentExtractionService } from './email-commitment-extraction.service';

describe('EmailCommitmentExtractionService', () => {
  function buildService(responseText: string) {
    const fakeClient = {
      messages: {
        create: jest.fn().mockResolvedValue({ content: [{ type: 'text', text: responseText }] }),
      },
    } as any;
    return new EmailCommitmentExtractionService(fakeClient);
  }

  it('returns the parsed commitment when the LLM identifies one', async () => {
    const service = buildService(
      JSON.stringify({
        tituloCompromisso: 'Enviar relatório',
        dataHoraLimite: '2026-08-15T15:00:00',
        antecedenciaMinutos: 1440,
      }),
    );

    const result = await service.extrair('Envio o relatório até sexta às 15h.');

    expect(result).toEqual({
      tituloCompromisso: 'Enviar relatório',
      dataHoraLimite: '2026-08-15T15:00:00',
      antecedenciaMinutos: 1440,
    });
  });

  it('returns null when the LLM finds no commitment', async () => {
    const service = buildService('null');

    const result = await service.extrair('Ok, obrigado!');

    expect(result).toBeNull();
  });

  it('returns null (never throws) when the LLM response is malformed', async () => {
    const service = buildService('not json and not the word null either');

    const result = await service.extrair('Envio amanhã.');

    expect(result).toBeNull();
  });

  it('normalizes any antecedenciaMinutos other than 60 to 1440', async () => {
    const service = buildService(
      JSON.stringify({
        tituloCompromisso: 'Ligar',
        dataHoraLimite: '2026-08-15T10:00:00',
        antecedenciaMinutos: 999,
      }),
    );

    const result = await service.extrair('Te ligo amanhã de manhã.');

    expect(result?.antecedenciaMinutos).toBe(1440);
  });
});
