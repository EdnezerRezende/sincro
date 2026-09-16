import { readFileSync } from 'fs';
import { join } from 'path';
import {
  CABECA_TIPO,
  EmailFinanceRegexParserService,
  FINANCE_PARSER_VERSION,
} from './email-finance-regex-parser.service';
import { triagem } from './finance-email-detector';
import type { AnexoMeta } from './finance-evidence';

const fx = (name: string) =>
  readFileSync(join(__dirname, '__fixtures__', name), 'utf-8');
const utc = (y: number, m: number, d: number) =>
  new Date(Date.UTC(y, m - 1, d));
const pdf = (filename: string): AnexoMeta => ({
  filename,
  mimeType: 'application/pdf',
  size: 1000,
  attachmentId: 'a1',
});

describe('EmailFinanceRegexParserService.parse', () => {
  const service = new EmailFinanceRegexParserService();
  const parse = (
    remetente: string,
    assunto: string,
    corpo: string,
    recebidoEm: Date,
    anexos: AnexoMeta[] = [],
    marcado = false,
  ) =>
    service.parse({
      remetente,
      assunto,
      corpo,
      recebidoEm,
      triagem: triagem(remetente, assunto, { marcado }),
      anexos,
    });

  it('exports the parser version', () =>
    expect(FINANCE_PARSER_VERSION).toBe(2));

  describe('e-mails reais', () => {
    it('Nubank fatura fechada: forte, valor null, data inferida do "15 de setembro"', () => {
      const r = parse(
        'Nubank <todomundo@nubank.com.br>',
        'A fatura do seu cartão Nubank está fechada',
        fx('nubank-fatura-fechada-real.txt'),
        new Date('2026-09-08T04:37:16Z'),
        [pdf('Nubank_2026-09-15.pdf')],
      );
      expect(r).toMatchObject({
        tipo: 'FATURA_CARTAO',
        instituicao: 'Nubank',
        valor: null,
        dataVencimento: utc(2026, 9, 15),
        dataEncontrada: true,
        codigoBarras: null,
      });
    });
    it('Santander: cartão no corpo → FATURA_CARTAO, "no valor de" extrai 111,46', () => {
      const r = parse(
        'Santander <faturaporemail@santander.com.br>',
        'Fatura por e-mail - Agosto/2026',
        fx('santander-fatura-por-email.txt'),
        new Date('2026-08-04T21:30:05Z'),
      );
      expect(r).toMatchObject({
        tipo: 'FATURA_CARTAO',
        instituicao: 'Santander',
        valor: 111.46,
        dataVencimento: utc(2026, 8, 10),
      });
    });
    it.each([
      'leroy-pefisa-celebre.txt',
      'leroy-pefisa-celebre-minificado.txt',
    ])('Leroy/Pefisa (%s): 520,61 e 17/09, nunca a parcela', (f) => {
      const r = parse(
        'Leroy Merlin Pay <noreply@leroymerlinpay.pefisa.com.br>',
        'A fatura do seu Cartão Celebre! Elo chegou!',
        fx(f),
        new Date('2026-09-15T12:04:12Z'),
      );
      expect(r).toMatchObject({
        tipo: 'FATURA_CARTAO',
        instituicao: 'Pefisa',
        valor: 520.61,
        dataVencimento: utc(2026, 9, 17),
      });
      expect(r?.valor).not.toBe(86.33);
    });
    it('Starlink: fraco aceito por E5/E6', () => {
      const r = parse(
        'Starlink <no-reply@starlink.com>',
        'Fatura da Starlink',
        fx('starlink-fatura.txt'),
        new Date('2026-08-27T01:31:34Z'),
        [pdf('fatura-starlink.pdf')],
      );
      expect(r).toMatchObject({
        tipo: 'DESPESA',
        instituicao: 'Starlink',
        valor: null,
      });
    });
    it('Porto: forte por S3, valor e vencimento do corpo', () => {
      const r = parse(
        'Porto Consórcio <portoconsorcio@portoseguro.com.br>',
        'Informativo Consórcio Porto Bank',
        fx('porto-consorcio.txt'),
        new Date('2026-09-15T01:04:36Z'),
      );
      expect(r).toMatchObject({
        tipo: 'DESPESA',
        valor: 1345.51,
        dataVencimento: utc(2026, 9, 20),
      });
    });
    it('Pefisa em atraso: fraco aceito por E2 (assunto tem "fatura")', () => {
      const r = parse(
        'Pefisa <pagamento@pefisa.com.br>',
        'Sua Fatura CELEBRE! ELO MAIS',
        fx('pefisa-em-atraso.txt'),
        new Date('2026-07-24T11:13:35Z'),
      );
      expect(r).toMatchObject({
        valor: 522.88,
        dataVencimento: utc(2026, 7, 17),
      });
    });
    it('Neoenergia "escolha como receber": veto na triagem → null', () => {
      expect(
        parse(
          'Neoenergia <cliente@neoenergiabrasilia.com.br>',
          'Escolha como receber sua conta de luz',
          fx('neoenergia-escolha-conta-luz.txt'),
          new Date(),
        ),
      ).toBeNull();
    });
    it('pagamento recebido no corpo derruba um forte; marcador ignora a negativa', () => {
      const rem = 'Nubank <todomundo@nubank.com.br>',
        ass = 'A fatura do seu cartão está fechada';
      expect(
        parse(rem, ass, fx('pagamento-recebido.txt'), new Date()),
      ).toBeNull();
      expect(
        parse(rem, ass, fx('pagamento-recebido.txt'), new Date(), [], true),
      ).not.toBeNull();
    });
    it('Sam\'s Club "vence em breve", sem valor/data no corpo: FATURA_CARTAO, dataVencimento = recebidoEm', () => {
      const recebidoEm = new Date('2026-09-16T10:00:00Z');
      const r = parse(
        "Sam's Club <cartaosamsclub@sams.cartaosamsclub.com.br>",
        "A fatura do seu Cartão de Crédito Sam's Club vence em breve! Confira as formas de pagamento.",
        fx('sams-vence-em-breve.txt'),
        recebidoEm,
      );
      expect(r).toMatchObject({
        tipo: 'FATURA_CARTAO',
        instituicao: "Sam's Club",
        valor: null,
        dataVencimento: recebidoEm,
        dataEncontrada: false,
      });
    });
  });

  describe('CABECA_TIPO / bandeira "elo"', () => {
    it('"cartão" fora da cabeça (a partir do char 601) não muda o tipo para remetente desconhecido', () => {
      const corpo = `${'x'.repeat(CABECA_TIPO)} fatura do seu cartão`;
      const r = parse(
        'X <contato@empresadesconhecida.com.br>',
        'Seu boleto chegou',
        corpo,
        new Date('2026-09-01T00:00:00Z'),
      );
      expect(r?.tipo).toBe('DESPESA');
    });
    it('"elo" sozinho perto de "fatura" não vira FATURA_CARTAO (não é bandeira nem "cartão")', () => {
      const r = parse(
        'X <contato@lojaelo.com.br>',
        'Sua fatura Elo chegou',
        'Confira os detalhes no aplicativo.',
        new Date('2026-09-01T00:00:00Z'),
      );
      expect(r?.tipo).toBe('DESPESA');
    });
  });

  describe('instituições desconhecidas criam; adversariais não', () => {
    it.each([
      [
        'Banco Alfa <fatura@bancoalfa.com.br>',
        'Sua fatura Alfa Visa fechou',
        'instituicao-desconhecida/banco-alfa.txt',
        'FATURA_CARTAO',
        null,
      ],
      [
        'Coop Beta <contato@coopbeta.coop.br>',
        'Boleto da mensalidade de outubro',
        'instituicao-desconhecida/coop-beta.txt',
        'DESPESA',
        250,
      ],
      [
        'Gama <no-reply@gamapay.com>',
        'Vencimento amanhã: R$ 89,90',
        'instituicao-desconhecida/fintech-gama.txt',
        'DESPESA',
        89.9,
      ],
    ])('%s cria', (rem, ass, f, tipo, valor) => {
      expect(
        parse(rem, ass, fx(f), new Date('2026-09-01T00:00:00Z')),
      ).toMatchObject({ tipo, valor });
    });
    it.each([
      ['Você recebeu um Pix de Fulano', 'adversarial-corpo/pix-recebido.txt'],
      ['Compra aprovada', 'adversarial-corpo/compra-aprovada.txt'],
      [
        'Transferência realizada',
        'adversarial-corpo/transferencia-realizada.txt',
      ],
      ['Rendimento da caixinha', 'adversarial-corpo/rendimento-caixinha.txt'],
      ['Seu cartão foi entregue', 'adversarial-corpo/cartao-entregue.txt'],
      ['Resumo das suas compras', 'adversarial-corpo/resumo-compras.txt'],
      [
        'Informativo de limite',
        'adversarial-corpo/informativo-limite-zero.txt',
      ],
    ])('%s de nubank (fraco por S7) → null', (ass, f) => {
      expect(
        parse(
          'Nubank <todomundo@nubank.com.br>',
          ass,
          fx(f),
          new Date('2026-09-01T00:00:00Z'),
        ),
      ).toBeNull();
    });
    it('escola: "vence dia 10" aceito por E2 com "mensalidade" no assunto', () => {
      const r = parse(
        'Escola X <financeiro@escolax.com.br>',
        'Mensalidade de outubro',
        'A mensalidade vence dia 10 — valor R$ 1.200,00. Boleto disponível no portal.',
        new Date('2026-09-25T00:00:00Z'),
      );
      expect(r).toMatchObject({
        tipo: 'DESPESA',
        dataVencimento: utc(2026, 10, 10),
      });
    });
    it('telecom desconhecida: "Sua conta chegou" + valor a pagar + vencimento → DESPESA', () => {
      const r = parse(
        'Telecom Z <contato@telecomz.com.br>',
        'Sua conta chegou',
        'Sua conta chegou\nVencimento 20/09\nValor a pagar R$ 129,90\nPague no cartão de crédito',
        new Date('2026-09-01T00:00:00Z'),
      );
      expect(r).toMatchObject({
        tipo: 'DESPESA',
        valor: 129.9,
        dataVencimento: utc(2026, 9, 20),
      });
    });
  });

  describe('regressões preservadas', () => {
    const recebidoEm = utc(2026, 9, 1);
    it('Nubank com valor (fixture antiga)', () => {
      expect(
        parse(
          'Nubank <fatura@nubank.com.br>',
          'Sua fatura fechou',
          fx('nubank-fatura-fechou-com-valor.txt'),
          recebidoEm,
        ),
      ).toMatchObject({
        tipo: 'FATURA_CARTAO',
        valor: 1234.56,
        dataVencimento: utc(2026, 10, 10),
      });
    });
    it('Itaú boleto 47 dígitos', () => {
      expect(
        parse(
          'Itaú <boletos@itau.com.br>',
          'Boleto disponível',
          fx('itau-boleto-linha-digitavel.txt'),
          recebidoEm,
        ),
      ).toMatchObject({
        codigoBarras: '34191.79001 01043.510047 91020.150008 1 84410000012345',
        valor: 452.1,
        tipo: 'DESPESA',
      });
    });
    it('Enel 48 dígitos', () => {
      expect(
        parse(
          'Enel <faturas@enel.com.br>',
          'Sua conta de luz chegou',
          fx('enel-conta-luz-48-digitos.txt'),
          recebidoEm,
        )?.codigoBarras,
      ).toBe('82660000001-2 23400012345-6 78900001234-5 60000000000-1');
    });
    it('marketing de fatura de remetente desconhecido não cria', () => {
      expect(
        parse(
          'X <contato@bancoz.com.br>',
          'Parcelamento da fatura agora disponível no app',
          'Parcele a partir de R$ 99,90. Campanha válida até 31/12/2026.',
          recebidoEm,
        ),
      ).toBeNull();
      expect(
        parse(
          'X <contato@bancoz.com.br>',
          'Nova função: fatura em PDF já disponível',
          'Baixe no app.',
          recebidoEm,
        ),
      ).toBeNull();
    });
    it('conta de luz que anuncia "pague no cartão" continua DESPESA', () => {
      expect(
        parse(
          'Vivo <faturas@vivo.com.br>',
          'Sua fatura Vivo chegou: pague no cartão de crédito',
          'Valor a pagar R$ 99,90 Vencimento 10/10/2026',
          recebidoEm,
        )?.tipo,
      ).toBe('DESPESA');
    });
    it('"Sua fatura chegou" (lifecycle) de instituição CARTAO → FATURA_CARTAO', () => {
      const r = parse(
        'Itaú <fatura@itau.com.br>',
        'Sua fatura chegou',
        'Total da fatura: R$ 800,00\nVencimento: 10/10/2026',
        recebidoEm,
      );
      expect(r).toMatchObject({
        tipo: 'FATURA_CARTAO',
        valor: 800,
        dataVencimento: utc(2026, 10, 10),
      });
    });
  });

  describe('complementarComTexto', () => {
    const service2 = new EmailFinanceRegexParserService();
    const base = {
      tipo: 'FATURA_CARTAO' as const,
      descricao: 'x',
      instituicao: 'Nubank',
      valor: null,
      dataVencimento: utc(2026, 9, 8),
      dataEncontrada: false,
      codigoBarras: null,
    };
    it('fills only missing fields', () => {
      const r = service2.complementarComTexto(
        base,
        'Total da fatura R$ 1.234,56\nVencimento 15/09/2026',
        new Date('2026-09-08T00:00:00Z'),
      );
      expect(r).toMatchObject({
        valor: 1234.56,
        dataVencimento: utc(2026, 9, 15),
        dataEncontrada: true,
      });
      const r2 = service2.complementarComTexto(
        { ...base, valor: 10, dataEncontrada: true },
        'Total da fatura R$ 1.234,56\nVencimento 15/09/2026',
        new Date(),
      );
      expect(r2).toMatchObject({ valor: 10, dataVencimento: utc(2026, 9, 8) });
    });
    it('null text is a no-op', () => {
      expect(service2.complementarComTexto(base, null, new Date())).toEqual(
        base,
      );
    });
  });
});
