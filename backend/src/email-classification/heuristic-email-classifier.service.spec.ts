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

  it('classifies as PRECISA_ATENCAO for a card invoice subject that never says "vencimento"/"vence"', async () => {
    const result = await classifier.classify(
      { remetente: 'cartao@meubanco.com.br', assunto: 'A fatura do seu cartão chegou', corpo: 'Confira os detalhes no app.' },
      {},
    );

    expect(result.categoria).toBe('PRECISA_ATENCAO');
  });

  it('does NOT classify a payment receipt/confirmation as PRECISA_ATENCAO, even when the subject mentions "fatura do cartão"', async () => {
    const result = await classifier.classify(
      {
        remetente: 'x@nubank.com.br',
        assunto: 'Recibo: pagamento da sua fatura do cartão confirmado',
        corpo: 'Recebemos R$ 1.500,00.',
      },
      {},
    );

    expect(result.categoria).toBe('PODE_ESPERAR');
  });

  it.each([
    ['conditional boilerplate ("caso o pagamento já tenha sido confirmado")', 'Confira os detalhes no app. Caso o pagamento já tenha sido confirmado, desconsidere esta mensagem.'],
    ['an unrelated retention-policy footer', 'O comprovante de pagamento fica disponível por 90 dias.'],
    ['a mention of the PREVIOUS cycle being paid, not this one', 'Lembrete: sua fatura anterior foi paga em 05/08. Esta é a nova fatura.'],
  ])(
    'still classifies a genuinely pending invoice as PRECISA_ATENCAO even when the BODY contains settled-payment-like boilerplate: %s',
    async (_label, corpo) => {
      const result = await classifier.classify(
        { remetente: 'x@meubanco.com.br', assunto: 'A fatura do seu cartão chegou', corpo },
        {},
      );

      expect(result.categoria).toBe('PRECISA_ATENCAO');
    },
  );

  it('the settled-payment veto overrides the urgency-keyword list too, not just the card-invoice signal', async () => {
    const result = await classifier.classify(
      {
        remetente: 'x@nubank.com.br',
        assunto: 'Recibo: pagamento da sua fatura do cartão confirmado',
        corpo: 'Sua próxima fatura vence em 10/10/2026.',
      },
      {},
    );

    expect(result.categoria).toBe('PODE_ESPERAR');
  });

  it('does NOT classify a marketing e-mail as PRECISA_ATENCAO just because its BODY mentions "fatura do cartão" (card-invoice check is subject-only)', async () => {
    const result = await classifier.classify(
      {
        remetente: 'news@lojaxyz.com.br',
        assunto: 'Novidades da semana na Loja XYZ',
        corpo: 'Compre agora e parcele no cartão: pague depois na fatura do seu cartão, sem juros.',
      },
      {},
    );

    expect(result.categoria).toBe('PODE_ESPERAR');
  });

  it('truncates a long subject to build resumoCurto', async () => {
    const longSubject = 'A'.repeat(150);
    const result = await classifier.classify({ remetente: 'x@example.com', assunto: longSubject, corpo: '' }, {});

    expect(result.resumoCurto.length).toBeLessThanOrEqual(100);
    expect(result.resumoCurto.endsWith('...')).toBe(true);
  });
});
