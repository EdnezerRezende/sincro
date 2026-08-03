import { HeuristicEmailClassifier } from './heuristic-email-classifier.service';

describe('HeuristicEmailClassifier', () => {
  const classifier = new HeuristicEmailClassifier();

  it('classifies as PRECISA_ATENCAO when the subject contains an urgency keyword', async () => {
    const result = await classifier.classify(
      { remetente: 'banco@example.com', assunto: 'Fatura com vencimento amanhã', corpo: 'Pague até amanhã.' },
      {},
    );

    expect(result.categoria).toBe('PRECISA_ATENCAO');
  });

  it('classifies as PRECISA_ATENCAO when the body contains an urgency keyword even if the subject does not', async () => {
    const result = await classifier.classify(
      { remetente: 'rh@example.com', assunto: 'Atualização', corpo: 'Ação necessária até sexta-feira.' },
      {},
    );

    expect(result.categoria).toBe('PRECISA_ATENCAO');
  });

  it('classifies as PODE_ESPERAR when there is no urgency keyword', async () => {
    const result = await classifier.classify(
      { remetente: 'newsletter@example.com', assunto: 'Novidades da semana', corpo: 'Confira o que rolou.' },
      {},
    );

    expect(result.categoria).toBe('PODE_ESPERAR');
  });

  it('does NOT classify as PRECISA_ATENCAO when a keyword only appears as a substring of another word', async () => {
    const result = await classifier.classify(
      {
        remetente: 'marketing@example.com',
        assunto: 'Deixe nosso time te convencer',
        corpo: 'Um argumento bem convincente para você conhecer o produto.',
      },
      {},
    );

    expect(result.categoria).toBe('PODE_ESPERAR');
  });

  it('does NOT classify as PRECISA_ATENCAO for a generic "importante" marketing footer (dropped keyword)', async () => {
    const result = await classifier.classify(
      {
        remetente: 'newsletter@example.com',
        assunto: 'Novidades da semana',
        corpo: 'Informação importante sobre nossos produtos e novidades.',
      },
      {},
    );

    expect(result.categoria).toBe('PODE_ESPERAR');
  });

  it('still classifies as PRECISA_ATENCAO when "vence" appears as a standalone word', async () => {
    const result = await classifier.classify(
      { remetente: 'banco@example.com', assunto: 'Seu boleto vence hoje', corpo: '' },
      {},
    );

    expect(result.categoria).toBe('PRECISA_ATENCAO');
  });

  it('truncates a long subject to build resumoCurto', async () => {
    const longSubject = 'A'.repeat(150);
    const result = await classifier.classify({ remetente: 'x@example.com', assunto: longSubject, corpo: '' }, {});

    expect(result.resumoCurto.length).toBeLessThanOrEqual(100);
    expect(result.resumoCurto.endsWith('...')).toBe(true);
  });
});
