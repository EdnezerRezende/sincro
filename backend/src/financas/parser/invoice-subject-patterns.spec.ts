import { isCardInvoiceSubject, isSettledPaymentSubject } from './invoice-subject-patterns';

describe('isCardInvoiceSubject', () => {
  it.each([
    'A fatura do seu cartão chegou',
    'Cartão de crédito: fatura disponível',
    'Faturas do seu cartão de crédito',
  ])('matches "%s"', (assunto) => {
    expect(isCardInvoiceSubject(assunto)).toBe(true);
  });

  it.each([
    'Sua fatura já está fechada',
    'Parcele sua fatura em até 12x sem juros',
    'Sua fatura de energia elétrica chegou',
  ])('does NOT match "%s" (no "cartão" nearby)', (assunto) => {
    expect(isCardInvoiceSubject(assunto)).toBe(false);
  });

  it('matches accented "cartão" even when the header arrives Unicode-NFD (combining tilde)', () => {
    const nfd = 'A fatura do seu cartão chegou'; // "cartão" decomposed as a + combining ~ + o
    expect(nfd.normalize('NFC')).not.toBe(nfd); // sanity: the raw string really is decomposed
    expect(isCardInvoiceSubject(nfd)).toBe(true);
  });
});

describe('isSettledPaymentSubject', () => {
  it.each([
    'Recibo: pagamento da sua fatura do cartão confirmado',
    'Sua fatura do cartão foi paga',
    'Fatura do cartão quitada',
    'Comprovante de pagamento da fatura do cartão',
  ])('treats "%s" as settled', (text) => {
    expect(isSettledPaymentSubject(text)).toBe(true);
  });

  it.each([
    'Sua fatura ainda não foi paga',
    'Pagamento da sua fatura não confirmado',
    'Sua fatura do cartão não foi quitada',
    'Identificamos que sua fatura do cartão não foi paga',
    'Seu pagamento não foi confirmado — regularize sua fatura do cartão',
    'Fatura em aberto: não paga até o vencimento',
  ])('does NOT treat "%s" as settled (negation) — an overdue invoice must stay visible, not be silently dropped', (text) => {
    expect(isSettledPaymentSubject(text)).toBe(false);
  });

  it.each([
    ['boleto boilerplate, not a payment confirmation', 'Boleto disponível - recibo do sacado em anexo'],
    ['unrelated "recibo"', 'Requisição de recibo fiscal'],
    ['"quitad" as a substring of an unrelated word, not a whole word', 'Fatura do cartão Requitada'],
  ])('does NOT treat %s as settled: "%s"', (_label, text) => {
    expect(isSettledPaymentSubject(text)).toBe(false);
  });

  it.each([
    'Sua fatura do cartão final 1234 não consta em nosso sistema como quitada',
    'Informamos que sua fatura do cartão não foi identificada como quitada',
    'Sua fatura do cartão não foi, até o momento, quitada',
    'Não conseguimos localizar em nosso sistema o recibo de pagamento da sua fatura',
    'Nunca recebemos, desde o mês passado, o comprovante de pagamento da sua fatura',
    'Sua fatura ainda jamais foi paga',
  ])(
    'does NOT treat a longer, realistic negated sentence as settled (negation must not fall outside a fixed char window): "%s"',
    (text) => {
      expect(isSettledPaymentSubject(text)).toBe(false);
    },
  );

  it.each([
    'Recebemos o pagamento da sua fatura do cartão',
    'Confirmamos o pagamento da sua fatura',
    'Pagamento recebido: sua fatura do cartão',
    'Débito automático realizado para sua fatura do cartão',
    'Sua fatura do cartão foi cancelada',
    'Sua fatura do cartão foi estornada',
  ])('treats an active-voice confirmation or a cancelled/reversed invoice as settled: "%s"', (text) => {
    expect(isSettledPaymentSubject(text)).toBe(true);
  });

  it.each([
    ['a reassurance opener, not a negation of the settled phrase that follows', 'Não se preocupe, o pagamento da sua fatura do cartão foi confirmado com sucesso'],
    ['an unrelated clause before the colon', 'Não identificamos pendências: sua fatura do cartão está quitada'],
    ['a reassurance paraphrase ("não precisa se preocupar")', 'Não precisa se preocupar, o pagamento da sua fatura do cartão foi confirmado'],
    ['a reassurance paraphrase ("não faça nada")', 'Não faça nada, recebemos o pagamento da sua fatura do cartão'],
    ['a reassurance paraphrase ("não se assuste")', 'Não se assuste, sua fatura do cartão já está quitada'],
  ])(
    'does NOT let an unrelated earlier negation over-block a genuinely settled clause: %s ("%s")',
    (_label, text) => {
      expect(isSettledPaymentSubject(text)).toBe(true);
    },
  );

  it.each([
    ['negation before a colon-introduced continuation stays scoped correctly', 'Não conseguimos localizar o seguinte: recibo de pagamento da sua fatura do cartão'],
    ['negation stays scoped across a colon when genuinely related', 'Ainda não temos novidades: sua fatura do cartão foi paga?'],
  ])('does NOT treat %s as settled: "%s"', (_label, text) => {
    expect(isSettledPaymentSubject(text)).toBe(false);
  });

  it.each([
    ['an unrelated auto-debit cancellation, invoice still due', 'Débito automático cancelado: pague sua fatura do cartão até 10/10'],
    ['the CARD (not the invoice) being cancelled — a new invoice is due', 'Seu cartão foi cancelado — fatura final do cartão disponível'],
    ['a reissued invoice after the old card was cancelled', 'Sua fatura foi reemitida após o cartão anterior ter sido cancelado'],
    ['an installment plan cancellation, invoice still open', 'Parcelamento cancelado: sua fatura do cartão segue em aberto'],
  ])('does NOT treat %s as settled (only fatura/pagamento itself being cancelled counts): "%s"', (_label, text) => {
    expect(isSettledPaymentSubject(text)).toBe(false);
  });
});
