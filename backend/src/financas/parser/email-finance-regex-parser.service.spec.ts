import { readFileSync } from 'fs';
import { join } from 'path';
import { EmailFinanceRegexParserService } from './email-finance-regex-parser.service';

function fixture(name: string): string {
  return readFileSync(join(__dirname, '__fixtures__', name), 'utf-8');
}

describe('EmailFinanceRegexParserService — parse', () => {
  const service = new EmailFinanceRegexParserService({} as any);
  const recebidoEm = new Date(Date.UTC(2026, 8, 1));

  it('extracts value and due date from a closed Nubank invoice', () => {
    const result = service.parse({
      remetente: 'Nubank <fatura@nubank.com.br>',
      assunto: 'Sua fatura fechou',
      corpo: fixture('nubank-fatura-fechou-com-valor.txt'),
      recebidoEm,
    });
    expect(result).toEqual({
      tipo: 'FATURA_CARTAO',
      descricao: 'Sua fatura fechou',
      instituicao: 'Nubank',
      valor: 1234.56,
      dataVencimento: new Date(Date.UTC(2026, 9, 10)),
      codigoBarras: null,
    });
  });

  it('falls back to a null value and the received date when the invoice has no amount', () => {
    const result = service.parse({
      remetente: 'Nubank <fatura@nubank.com.br>',
      assunto: 'Sua fatura fechou',
      corpo: fixture('nubank-fatura-fechou-sem-valor.txt'),
      recebidoEm,
    });
    expect(result?.valor).toBeNull();
    expect(result?.dataVencimento).toEqual(recebidoEm);
  });

  it('extracts a 47-digit boleto linha digitável and its value', () => {
    const result = service.parse({
      remetente: 'Itaú <boletos@itau.com.br>',
      assunto: 'Boleto disponível',
      corpo: fixture('itau-boleto-linha-digitavel.txt'),
      recebidoEm,
    });
    expect(result?.codigoBarras).toBe('34191.79001 01043.510047 91020.150008 1 84410000012345');
    expect(result?.valor).toBe(452.1);
    expect(result?.tipo).toBe('DESPESA');
  });

  it('extracts a 48-digit concessionária linha digitável', () => {
    const result = service.parse({
      remetente: 'Enel <faturas@enel.com.br>',
      assunto: 'Sua conta de luz chegou',
      corpo: fixture('enel-conta-luz-48-digitos.txt'),
      recebidoEm,
    });
    expect(result?.codigoBarras).toBe('82660000001-2 23400012345-6 78900001234-5 60000000000-1');
    expect(result?.instituicao).toBe('Enel');
  });

  it('prioritizes "valor a pagar" over an unrelated currency mention', () => {
    const result = service.parse({
      remetente: 'Nubank <fatura@nubank.com.br>',
      assunto: 'Sua fatura está disponível',
      corpo: fixture('email-com-multiplos-valores-ambiguos.txt'),
      recebidoEm,
    });
    expect(result?.valor).toBe(340);
  });

  it('ignores emails from senders outside the mapped institution list', () => {
    const result = service.parse({
      remetente: 'Loja XYZ <contato@lojaxyz.com.br>',
      assunto: 'Promoção imperdível',
      corpo: fixture('email-remetente-desconhecido.txt'),
      recebidoEm,
    });
    expect(result).toBeNull();
  });

  it('parses a spelled-out Portuguese date', () => {
    const result = service.parse({
      remetente: 'Itaú <boletos@itau.com.br>',
      assunto: 'Boleto disponível',
      corpo: fixture('data-por-extenso.txt'),
      recebidoEm,
    });
    expect(result?.dataVencimento).toEqual(new Date(Date.UTC(2026, 9, 15)));
  });

  it('recognizes a card invoice from a sender outside INSTITUTION_MAP via the subject line', () => {
    const result = service.parse({
      remetente: 'Cartão MeuBanco <naoresponda@meubanco.com.br>',
      assunto: 'A fatura do seu cartão chegou',
      corpo: fixture('cartao-desconhecido-fatura.txt'),
      recebidoEm,
    });
    expect(result).toEqual({
      tipo: 'FATURA_CARTAO',
      descricao: 'A fatura do seu cartão chegou',
      instituicao: 'Meubanco',
      valor: 789,
      dataVencimento: new Date(Date.UTC(2026, 10, 20)),
      codigoBarras: null,
    });
  });

  it('extracts the sender address out of a trailing comment instead of failing to find a domain', () => {
    const result = service.parse({
      remetente: 'Fulano <naoresponda@meubanco.com.br> (não responda a este e-mail)',
      assunto: 'A fatura do seu cartão chegou',
      corpo: fixture('cartao-desconhecido-fatura.txt'),
      recebidoEm,
    });
    expect(result?.instituicao).toBe('Meubanco');
  });

  it('picks the first address out of a header with multiple addresses, not the last', () => {
    const result = service.parse({
      remetente: '"MeuBanco" <naoresponda@meubanco.com.br>, outro@dominio-y.com',
      assunto: 'A fatura do seu cartão chegou',
      corpo: fixture('cartao-desconhecido-fatura.txt'),
      recebidoEm,
    });
    expect(result?.instituicao).toBe('Meubanco');
  });

  it('skips a generic mailer/subdomain label when deriving the institution name', () => {
    const result = service.parse({
      remetente: 'Cartão <no-reply@mail.meubanco.com>',
      assunto: 'Sua fatura do cartão fechou',
      corpo: fixture('cartao-desconhecido-fatura.txt'),
      recebidoEm,
    });
    expect(result?.instituicao).toBe('Meubanco');
  });

  it('does not flip a mapped non-card institution (Vivo) into FATURA_CARTAO just because the subject says "fatura"', () => {
    const result = service.parse({
      remetente: 'Vivo <faturas@vivo.com.br>',
      assunto: 'Sua fatura Vivo já está disponível',
      corpo: fixture('email-remetente-desconhecido.txt'),
      recebidoEm,
    });
    expect(result?.tipo).toBe('DESPESA');
  });

  it('does not flip a mapped non-card institution (Enel) into FATURA_CARTAO for a generic invoice-lifecycle subject', () => {
    const result = service.parse({
      remetente: 'Enel <faturas@enel.com.br>',
      assunto: 'Nova fatura disponível',
      corpo: fixture('enel-conta-luz-48-digitos.txt'),
      recebidoEm,
    });
    expect(result?.tipo).toBe('DESPESA');
  });

  it('vetoes a payment-confirmation subject even from a mapped card-issuer sender, to avoid resurrecting a paid invoice as pending', () => {
    const result = service.parse({
      remetente: 'Nubank <fatura@nubank.com.br>',
      assunto: 'Pagamento da sua fatura confirmado',
      corpo: 'Recebemos o pagamento de R$ 1.500,00 em 01/09/2026.',
      recebidoEm,
    });
    expect(result).toBeNull();
  });

  it('does NOT veto a subject saying the invoice is still unpaid — negation must not be read as settled', () => {
    const result = service.parse({
      remetente: 'Nubank <fatura@nubank.com.br>',
      assunto: 'Sua fatura ainda não foi paga',
      corpo: 'Valor a pagar: R$ 1.200,00\nVencimento: 05/09/2026',
      recebidoEm,
    });
    expect(result).not.toBeNull();
    expect(result?.valor).toBe(1200);
  });

  it('refuses to create a lançamento from an unmapped sender whose subject mentions "fatura do cartão" but whose body has no real transactional data (likely an ad)', () => {
    const result = service.parse({
      remetente: 'promo@lojaxyz.com.br',
      assunto: 'Cashback de 5% na fatura do seu cartão',
      corpo: 'Sem valores aqui, só uma promoção.',
      recebidoEm,
    });
    expect(result).toBeNull();
  });

  it('refuses to create a lançamento from an unmapped sender when the only value/date in the body are UNANCHORED (a promotional price/campaign date, not a labeled due amount)', () => {
    const result = service.parse({
      remetente: 'promo@lojaxyz.com.br',
      assunto: 'Parcele a fatura do seu cartão em 12x sem juros',
      corpo: 'Simule agora: parcelas a partir de R$ 99,90. Campanha válida até 31/12/2026.',
      recebidoEm,
    });
    expect(result).toBeNull();
  });

  it.each([
    ['dd/mm/yy (2-digit year)', 'Valor da fatura: R$ 1.234,56\nVencimento: 05/09/26'],
    ['ISO date', 'Valor da fatura: R$ 1.234,56\nVencimento: 2026-09-05'],
    ['spelled-out date with a due-date anchor', 'Valor da fatura: R$ 1.234,56\nVence em 05 de setembro de 2026.'],
  ])('recognizes a legitimate unmapped-sender invoice in a common Brazilian date format: %s', (_label, corpo) => {
    const result = service.parse({
      remetente: 'no-reply@meubanco.com.br',
      assunto: 'A fatura do seu cartão está disponível',
      corpo,
      recebidoEm,
    });
    expect(result?.dataVencimento).toEqual(new Date(Date.UTC(2026, 8, 5)));
    expect(result?.valor).toBe(1234.56);
  });

  it('extracts the date AFTER the "Vencimento" label, not an earlier unrelated date on the same collapsed line', () => {
    const result = service.parse({
      remetente: 'Nubank <fatura@nubank.com.br>',
      assunto: 'Sua fatura fechou',
      corpo: 'Fechamento 28/09/2026 Vencimento 10/10/2026\nTotal da fatura: R$ 2.480,35',
      recebidoEm,
    });
    expect(result?.dataVencimento).toEqual(new Date(Date.UTC(2026, 9, 10)));
  });

  it('extracts the value AFTER the matched anchor, not an earlier unrelated currency (e.g. a minimum payment) on the same line', () => {
    const result = service.parse({
      remetente: 'Nubank <fatura@nubank.com.br>',
      assunto: 'Sua fatura fechou',
      corpo: 'Pagamento mínimo R$ 123,45 Total da fatura R$ 1.234,56\nVencimento: 10/10/2026',
      recebidoEm,
    });
    expect(result?.valor).toBe(1234.56);
  });

  it('extracts a currency amount with no thousand-separator dot (e.g. "R$ 2480,35")', () => {
    const result = service.parse({
      remetente: 'no-reply@meubanco.com.br',
      assunto: 'A fatura do seu cartão está disponível',
      corpo: 'Valor a pagar: R$ 2480,35\nVencimento: 10/10/2026',
      recebidoEm,
    });
    expect(result?.valor).toBe(2480.35);
  });

  it('finds the value/date on the NEXT line when the anchor label and its value are split across two lines (e.g. an HTML <div>label</div><div>value</div> pair collapsed to plain text)', () => {
    const result = service.parse({
      remetente: 'Nubank <fatura@nubank.com.br>',
      assunto: 'A fatura do seu cartão fechou',
      corpo: 'Total da fatura\nR$ 1.234,56\nVencimento\n10/10/2026',
      recebidoEm,
    });
    expect(result).toEqual({
      tipo: 'FATURA_CARTAO',
      descricao: 'A fatura do seu cartão fechou',
      instituicao: 'Nubank',
      valor: 1234.56,
      dataVencimento: new Date(Date.UTC(2026, 9, 10)),
      codigoBarras: null,
    });
  });

  it('skips a repeated anchor phrase followed by "após o vencimento" (a late-fee amount) and finds the real due value', () => {
    const result = service.parse({
      remetente: 'Itaú <boletos@itau.com.br>',
      assunto: 'Boleto disponível',
      corpo: 'Valor a pagar após o vencimento R$ 1.500,00 Valor a pagar até o vencimento R$ 1.234,56',
      recebidoEm,
    });
    expect(result?.valor).toBe(1234.56);
  });

  it.each(['Vivo <faturas@vivo.com.br>', 'Enel <faturas@enel.com.br>'] as const)(
    'keeps tipo DESPESA for a known non-card institution (%s) even when the subject mentions "cartão" as a payment method',
    (remetente) => {
      const result = service.parse({
        remetente,
        assunto: 'Sua fatura chegou: pague no cartão de crédito',
        corpo: 'Valor a pagar R$ 149,90\nVencimento 10/10/2026',
        recebidoEm,
      });
      expect(result?.tipo).toBe('DESPESA');
    },
  );

  it('refuses to create a lançamento from a MAPPED sender whose subject is card-invoice-shaped but whose body has only unanchored promotional data (marketing from the sender\'s own domain)', () => {
    const result = service.parse({
      remetente: 'Nubank <marketing@nubank.com.br>',
      assunto: 'Parcele a fatura do seu cartão em até 12x sem juros',
      corpo: 'Simule: parcelas a partir de R$ 99,90. Campanha válida até 30/09/2026.',
      recebidoEm,
    });
    expect(result).toBeNull();
  });

  it.each(['Nova função: fatura em PDF já disponível', 'Parcelamento da fatura agora disponível no app'])(
    'keeps tipo DESPESA for a mapped card issuer (Nubank) sending a promotional subject that merely mentions "fatura", not "sua fatura": "%s"',
    (assunto) => {
      const result = service.parse({
        remetente: 'Nubank <no-reply@nubank.com.br>',
        assunto,
        corpo: 'Confira: a partir de R$ 19,90. Válido até 30/09/2026.',
        recebidoEm,
      });
      expect(result?.tipo).toBe('DESPESA');
    },
  );

  it('still creates a lançamento for an unmapped sender when the body DOES carry a real value', () => {
    const result = service.parse({
      remetente: 'Cartão MeuBanco <naoresponda@meubanco.com.br>',
      assunto: 'A fatura do seu cartão chegou',
      corpo: fixture('cartao-desconhecido-fatura.txt'),
      recebidoEm,
    });
    expect(result?.valor).toBe(789);
  });

  it.each(['Sua fatura está disponível', 'Sua fatura foi gerada', 'Sua fatura foi emitida'])(
    'treats "%s" from a mapped card issuer (Nubank) as FATURA_CARTAO even without the literal word "fechou"',
    (assunto) => {
      const result = service.parse({
        remetente: 'Nubank <fatura@nubank.com.br>',
        assunto,
        corpo: 'nada relevante aqui',
        recebidoEm,
      });
      expect(result?.tipo).toBe('FATURA_CARTAO');
    },
  );
});

describe('EmailFinanceRegexParserService — matches', () => {
  const service = new EmailFinanceRegexParserService({} as any);

  it('returns true for a known institution domain', () => {
    expect(service.matches('Nubank <fatura@nubank.com.br>', 'Sua fatura fechou')).toBe(true);
  });

  it('returns false for a sender outside the mapped list', () => {
    expect(service.matches('Loja XYZ <contato@lojaxyz.com.br>', 'Promoção')).toBe(false);
  });

  it.each([
    'A fatura do seu cartão chegou',
    'Cartão de crédito: fatura disponível',
    'Faturas do seu cartão de crédito',
  ])('treats "%s" as a card-invoice subject regardless of sender', (assunto) => {
    expect(service.matches('alguem@dominio-qualquer.com', assunto)).toBe(true);
  });

  it.each([
    ['a bare "sua fatura" with no card context', 'Sua fatura já está fechada'],
    ['a bare "nova fatura" with no card context', 'Nova fatura disponível'],
    ['a marketing pitch that merely mentions "fatura"', 'Parcele sua fatura em até 12x sem juros'],
    ['a utility/phone bill subject', 'Sua fatura de energia elétrica chegou'],
    ['a condo bill subject', 'Nova fatura de condomínio disponível'],
  ])('does NOT match %s from an unmapped sender: "%s"', (_label, assunto) => {
    expect(service.matches('alguem@dominio-qualquer.com', assunto)).toBe(false);
  });

  it.each([
    'Recibo: pagamento da sua fatura do cartão confirmado',
    'Sua fatura do cartão foi paga',
    'Fatura do cartão quitada',
    'Comprovante de pagamento da fatura do cartão',
  ])('vetoes a settled-payment subject even when it also mentions "cartão": "%s"', (assunto) => {
    expect(service.matches('alguem@dominio-qualquer.com', assunto)).toBe(false);
  });
});

describe('EmailFinanceRegexParserService — processEmail', () => {
  function buildPrismaMock() {
    return {
      lancamentoFinanceiro: {
        findUnique: jest.fn().mockResolvedValue(null),
        create: jest.fn().mockResolvedValue({}),
      },
    };
  }

  it('creates a PENDENTE_REVISAO lançamento from a matched email', async () => {
    const prisma = buildPrismaMock();
    const service = new EmailFinanceRegexParserService(prisma as any);

    await service.processEmail(
      'user-1',
      {
        gmailMessageId: 'msg-1',
        remetente: 'Nubank <fatura@nubank.com.br>',
        assunto: 'Sua fatura fechou',
        recebidoEm: new Date(Date.UTC(2026, 8, 1)),
      },
      fixture('nubank-fatura-fechou-com-valor.txt'),
    );

    expect(prisma.lancamentoFinanceiro.create).toHaveBeenCalledWith({
      data: {
        userId: 'user-1',
        tipo: 'FATURA_CARTAO',
        descricao: 'Sua fatura fechou',
        instituicao: 'Nubank',
        valor: 1234.56,
        dataVencimento: new Date(Date.UTC(2026, 9, 10)),
        dataCompetencia: new Date(Date.UTC(2026, 9, 10)),
        status: 'PENDENTE_REVISAO',
        origem: 'EMAIL_PARSER',
        emailMessageId: 'msg-1',
        codigoBarras: null,
      },
    });
  });

  it('does not create a lançamento for an unmatched sender', async () => {
    const prisma = buildPrismaMock();
    const service = new EmailFinanceRegexParserService(prisma as any);

    await service.processEmail(
      'user-1',
      {
        gmailMessageId: 'msg-2',
        remetente: 'Loja XYZ <contato@lojaxyz.com.br>',
        assunto: 'Promoção',
        recebidoEm: new Date(Date.UTC(2026, 8, 1)),
      },
      fixture('email-remetente-desconhecido.txt'),
    );

    expect(prisma.lancamentoFinanceiro.create).not.toHaveBeenCalled();
  });

  it('never creates a second lançamento for an already-processed emailMessageId', async () => {
    const prisma = buildPrismaMock();
    prisma.lancamentoFinanceiro.findUnique.mockResolvedValue({ id: 'existing' });
    const service = new EmailFinanceRegexParserService(prisma as any);

    await service.processEmail(
      'user-1',
      {
        gmailMessageId: 'msg-1',
        remetente: 'Nubank <fatura@nubank.com.br>',
        assunto: 'Sua fatura fechou',
        recebidoEm: new Date(Date.UTC(2026, 8, 1)),
      },
      fixture('nubank-fatura-fechou-com-valor.txt'),
    );

    expect(prisma.lancamentoFinanceiro.findUnique).toHaveBeenCalledWith({
      where: { userId_emailMessageId: { userId: 'user-1', emailMessageId: 'msg-1' } },
    });
    expect(prisma.lancamentoFinanceiro.create).not.toHaveBeenCalled();
  });
});
