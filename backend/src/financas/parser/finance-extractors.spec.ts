import { extrairCodigoBarras, extrairDataVencimento, extrairValor, inferirAno, proximoDia } from './finance-extractors';

const rec = (iso: string) => new Date(iso);
const utc = (y: number, m: number, d: number) => new Date(Date.UTC(y, m - 1, d));

describe('extrairValor', () => {
  it('reads an anchored value without R$ (Leroy)', () => {
    expect(extrairValor('Vencimento: ..... 17/09\nValor total: ........ 520,61\nOPÇÃO 1: Pague em até 12 vezes de R$ 86,33')).toEqual({ valor: 520.61, anchored: true, ancoraCobranca: false });
  });
  it('reads "no valor de" (Santander) as extraction anchor, not cobrança anchor', () => {
    expect(extrairValor('está fechada no valor de R$ 111,46, com vencimento para o dia 10/08/2026.\n06 Parcelas de R$ 25,39')).toEqual({ valor: 111.46, anchored: true, ancoraCobranca: false });
  });
  it('flags a cobrança anchor', () => {
    expect(extrairValor('Valor a pagar: R$ 129,90')).toEqual({ valor: 129.9, anchored: true, ancoraCobranca: true });
  });
  it('keeps existing behaviour for collapsed table rows (mínimo before total on one line)', () => {
    expect(extrairValor('Pagamento mínimo R$ 123,45 Total da fatura R$ 1.234,56').valor).toBe(1234.56);
    expect(extrairValor('Valor a pagar após o vencimento R$ 1.500,00 Valor a pagar até o vencimento R$ 1.234,56').valor).toBe(1234.56);
  });
  it('rejects "após/mínimo" within the first 15 chars after the anchor, not just at the very start (labels with ":")', () => {
    expect(extrairValor('Valor a pagar: após o vencimento R$ 1.500,00 Valor a pagar: até o vencimento R$ 1.234,56').valor).toBe(1234.56);
    expect(extrairValor('Valor a pagar: (após o vencimento) R$ 1.500,00 Valor a pagar: até o vencimento R$ 1.234,56').valor).toBe(1234.56);
  });
  it('never takes a value from an installment segment or line', () => {
    expect(extrairValor('Valor total:\nOPÇÃO 1: Pague em até 12 vezes de R$ 86,33').valor).toBeNull();
    expect(extrairValor('Total da fatura: 12x de R$ 100,00').valor).toBeNull();
  });
  it('next-line fallback works for label/value split, but not into another anchor', () => {
    expect(extrairValor('Valor total\nR$ 300,00').valor).toBe(300);
    expect(extrairValor('Valor total\nValor mínimo R$ 50,00').valor).toBeNull();
  });
  it('Subtotal: does not match total:', () => {
    expect(extrairValor('Subtotal: R$ 120,00\nFrete: R$ 10,00').anchored).toBe(false);
  });
  it('unanchored fallback still needs R$ and a single occurrence', () => {
    expect(extrairValor('Você pagou R$ 50,00')).toEqual({ valor: 50, anchored: false, ancoraCobranca: false });
    expect(extrairValor('R$ 50,00 e R$ 60,00').valor).toBeNull();
    expect(extrairValor('juros de 2,99% e taxa 14,30').valor).toBeNull();
  });
  it('zero becomes null', () => {
    expect(extrairValor('Total da fatura atual: R$ 0,00').valor).toBeNull();
  });
});

describe('inferirAno / proximoDia', () => {
  it('picks the year nearest to recebidoEm', () => {
    expect(inferirAno(10, 1, rec('2026-12-28T00:00:00Z'))).toEqual(utc(2027, 1, 10));
    expect(inferirAno(28, 12, rec('2027-01-05T00:00:00Z'))).toEqual(utc(2026, 12, 28));
    expect(inferirAno(15, 9, rec('2026-09-08T00:00:00Z'))).toEqual(utc(2026, 9, 15));
  });
  it('rejects invalid dates instead of rolling them', () => {
    expect(inferirAno(31, 2, rec('2026-02-01T00:00:00Z'))).toBeNull();
  });
  it('proximoDia: next occurrence within 45 days, else null', () => {
    expect(proximoDia(10, rec('2026-09-01T00:00:00Z'))).toEqual(utc(2026, 9, 10));
    expect(proximoDia(5, rec('2026-09-20T00:00:00Z'))).toEqual(utc(2026, 10, 5));
    expect(proximoDia(40, rec('2026-09-01T00:00:00Z'))).toBeNull();
    expect(proximoDia(0, rec('2026-09-01T00:00:00Z'))).toBeNull();
  });
});

describe('extrairDataVencimento', () => {
  const r = rec('2026-09-08T04:37:16Z');
  it('reads "vence no dia 15 de setembro" without a year', () => {
    expect(extrairDataVencimento('Sua fatura já está fechada, vence no dia 15 de setembro e você pode conferir', r)).toEqual({ data: utc(2026, 9, 15), anchored: true });
  });
  it('reads "Vencimento: 17/09" without a year', () => {
    expect(extrairDataVencimento('Vencimento: ..................... 17/09\nValor total: 520,61', rec('2026-09-15T12:04:12Z'))).toEqual({ data: utc(2026, 9, 17), anchored: true });
  });
  it('reads day-only "vence dia 10"', () => {
    expect(extrairDataVencimento('A mensalidade vence dia 10 — valor R$ 1.200,00', rec('2026-09-01T00:00:00Z'))).toEqual({ data: utc(2026, 9, 10), anchored: true });
    expect(extrairDataVencimento('vence dia 40', rec('2026-09-01T00:00:00Z'))).toEqual({ data: null, anchored: false });
  });
  it('prefers the full-date format when a year is present', () => {
    expect(extrairDataVencimento('Vencimento: 10/10/2025', rec('2026-09-01T00:00:00Z'))).toEqual({ data: utc(2025, 10, 10), anchored: true });
  });
  it('keeps the existing anchored formats (dd/mm/yyyy after "vencimento", next-line split)', () => {
    expect(extrairDataVencimento('Fechamento 28/09/2026 Vencimento 10/10/2026', r).data).toEqual(utc(2026, 10, 10));
    expect(extrairDataVencimento('Vencimento\n10/10/2026', r).data).toEqual(utc(2026, 10, 10));
  });
  it('dd/mm without year is NOT read from the whole-body fallback', () => {
    expect(extrairDataVencimento('Parcela 3/12 do seu curso', r)).toEqual({ data: null, anchored: false });
  });
  it('whole-body fallback still reads a full date, unanchored', () => {
    expect(extrairDataVencimento('Campanha válida até 31/12/2026', r)).toEqual({ data: utc(2026, 12, 31), anchored: false });
  });
  it('"em N dias" is NOT a date, even right after an anchor', () => {
    expect(extrairDataVencimento('Sua fatura vence em 3 dias', rec('2026-09-10T00:00:00Z'))).toEqual({ data: null, anchored: false });
    expect(extrairDataVencimento('Vencimento em 5 dias', rec('2026-09-10T00:00:00Z'))).toEqual({ data: null, anchored: false });
    expect(extrairDataVencimento('Seu boleto vence em 2 dias', rec('2026-09-10T00:00:00Z'))).toEqual({ data: null, anchored: false });
  });
  it('next-line fallback also works when the label ends with ":" (trailing space or \\r\\n before the date)', () => {
    expect(extrairDataVencimento('Vencimento: \n10/10', rec('2026-09-01T00:00:00Z'))).toEqual({ data: utc(2026, 10, 10), anchored: true });
    expect(extrairDataVencimento('Vencimento:\r\n10/10/2026', rec('2026-09-01T00:00:00Z'))).toEqual({ data: utc(2026, 10, 10), anchored: true });
  });
  it('CONECTOR_RE accepts punctuation AND a connector word together ("Vencimento: dia 10")', () => {
    expect(extrairDataVencimento('Vencimento: dia 10', rec('2026-09-01T00:00:00Z'))).toEqual({ data: utc(2026, 9, 10), anchored: true });
    expect(extrairDataVencimento('Vencimento: no dia 10', rec('2026-09-01T00:00:00Z'))).toEqual({ data: utc(2026, 9, 10), anchored: true });
    expect(extrairDataVencimento('Vencimento - dia 10', rec('2026-09-01T00:00:00Z'))).toEqual({ data: utc(2026, 9, 10), anchored: true });
  });
  it('reads dotted/hyphenated full dates with a consistent separator (not misread as day-only)', () => {
    expect(extrairDataVencimento('Vencimento: 05.10.2026', rec('2026-09-01T00:00:00Z'))).toEqual({ data: utc(2026, 10, 5), anchored: true });
    expect(extrairDataVencimento('Vencimento: 05-10-2026', rec('2026-09-01T00:00:00Z'))).toEqual({ data: utc(2026, 10, 5), anchored: true });
  });
  it('keeps rejecting an invalid Feb 29 day-only anchor without year', () => {
    expect(extrairDataVencimento('Vencimento: 29/02', rec('2026-09-01T00:00:00Z'))).toEqual({ data: null, anchored: false });
  });
  it('keeps reading an unanchored full date nearest to the received year', () => {
    expect(extrairDataVencimento('10/10/2025', rec('2026-09-01T00:00:00Z')).data).toEqual(utc(2025, 10, 10));
  });
  it('keeps rejecting a day-only match too far away (60 days)', () => {
    expect(extrairDataVencimento('vence dia 31', rec('2026-09-01T00:00:00Z'))).toEqual({ data: null, anchored: false });
  });
});

describe('extrairCodigoBarras', () => {
  it('reads 47 and 48 digit lines', () => {
    expect(extrairCodigoBarras('x\n34191.79001 01043.510047 91020.150008 1 84410000012345\ny')).toBe('34191.79001 01043.510047 91020.150008 1 84410000012345');
    expect(extrairCodigoBarras('82660000001-2 23400012345-6 78900001234-5 60000000000-1')).toBe('82660000001-2 23400012345-6 78900001234-5 60000000000-1');
    expect(extrairCodigoBarras('nada')).toBeNull();
  });
});

// Testes adicionais (não do plano) — corpos reais da spec
// (docs/superpowers/specs/2026-09-15-financas-deteccao-email-v2-design.md), cobrindo valor +
// data juntos em três instituições distintas.
describe('extrairValor / extrairDataVencimento — corpos reais adicionais', () => {
  it('Nubank: "vence no dia 15 de setembro" → 2026-09-15 (recebido 2026-09-08)', () => {
    const texto = 'Olá, Fulano Sua fatura já está fechada, vence no dia 15 de setembro e você pode conferir todos os detalhes no PDF anexo aqui no e-mail.';
    expect(extrairDataVencimento(texto, rec('2026-09-08T04:37:16Z'))).toEqual({ data: utc(2026, 9, 15), anchored: true });
  });
  it('Santander: "no valor de R$ 111,46, com vencimento para o dia 10/08/2026" → 111.46 / 2026-08-10', () => {
    const texto = 'A fatura mensal do seu cartão SANTANDER ELITE MASTERCARD, final 9636, está fechada no valor de R$ 111,46, com vencimento para o dia 10/08/2026. A partir de hoje, todas as compras realizadas com o seu cartão serão lançadas na próxima fatura.';
    expect(extrairValor(texto).valor).toBe(111.46);
    expect(extrairDataVencimento(texto, rec('2026-08-04T21:30:05Z')).data).toEqual(utc(2026, 8, 10));
  });
  it('Porto: "no valor de R$ 1.345,51, com vencimento em 20/09/2026" → 1345.51 / 2026-09-20', () => {
    const texto = 'Chegou o informativo do seu Consórcio Porto Bank, cota 0010 grupo AF272, no valor de R$ 1.345,51, com vencimento em 20/09/2026.';
    expect(extrairValor(texto).valor).toBe(1345.51);
    expect(extrairDataVencimento(texto, rec('2026-09-15T01:04:36Z')).data).toEqual(utc(2026, 9, 20));
  });
});
