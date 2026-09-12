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
});

describe('EmailFinanceRegexParserService — matches', () => {
  const service = new EmailFinanceRegexParserService({} as any);

  it('returns true for a known institution domain', () => {
    expect(service.matches('Nubank <fatura@nubank.com.br>', 'Sua fatura fechou')).toBe(true);
  });

  it('returns false for a sender outside the mapped list', () => {
    expect(service.matches('Loja XYZ <contato@lojaxyz.com.br>', 'Promoção')).toBe(false);
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
