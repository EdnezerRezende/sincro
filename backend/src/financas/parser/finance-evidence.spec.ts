import { evidenciasDeCobranca, evidenciaSuficiente, temEvidenciaNegativa } from './finance-evidence';

const r = new Date('2026-09-01T00:00:00Z');
const ev = (texto: string, anexos: { filename: string }[] = []) =>
  evidenciasDeCobranca(texto, anexos.map((a) => ({ ...a, mimeType: 'application/pdf', size: 1, attachmentId: 'x' })), r);

describe('evidenciasDeCobranca', () => {
  it('E1 only with a cobrança anchor and value > 0', () => {
    expect(ev('Valor a pagar: R$ 129,90')).toEqual(new Set(['E1']));
    expect(ev('Você recebeu um Pix no valor de R$ 500,00')).toEqual(new Set());
    expect(ev('Valor: R$ 500,00')).toEqual(new Set());
    expect(ev('Total da fatura atual: R$ 0,00')).toEqual(new Set());
  });
  it('E2 with DATE_ANCHORS, including day-only', () => {
    expect(ev('A mensalidade vence dia 10 — valor R$ 1.200,00')).toEqual(new Set(['E2']));
    expect(ev('Vencimento da apólice 15/10/2026')).toEqual(new Set(['E2']));
    expect(ev('vencimento em breve')).toEqual(new Set());
  });
  it('E3 barcode, E4 pix + currency same/next line, E5 attached phrase, E6 attachment name', () => {
    expect(ev('34191.79001 01043.510047 91020.150008 1 84410000012345')).toEqual(new Set(['E3']));
    expect(ev('Pix copia e cola\nR$ 89,90')).toEqual(new Set(['E4']));
    expect(ev('Pix copia e cola\n\n\nR$ 89,90')).toEqual(new Set());
    expect(ev('Sua fatura da Starlink está anexada')).toEqual(new Set(['E5']));
    expect(ev('Olá', [{ filename: 'Fatura_082026.PDF' }])).toEqual(new Set(['E6']));
    expect(ev('Olá', [{ filename: 'Cobrança_09-2026.pdf' }])).toEqual(new Set(['E6']));
  });
  it('ignores text past CABECA_EVIDENCIA', () => {
    expect(ev(`${'x'.repeat(1500)} Valor a pagar: R$ 10,00`)).toEqual(new Set());
  });
});

describe('evidenciaSuficiente', () => {
  it('E1/E3/E4/E5/E6 alone suffice; E2 alone only with a cobrança noun in the subject', () => {
    expect(evidenciaSuficiente(new Set(['E1']), false)).toBe(true);
    expect(evidenciaSuficiente(new Set(['E6']), false)).toBe(true);
    expect(evidenciaSuficiente(new Set(['E2']), true)).toBe(true);
    expect(evidenciaSuficiente(new Set(['E2']), false)).toBe(false);
    expect(evidenciaSuficiente(new Set(), true)).toBe(false);
  });
});

describe('temEvidenciaNegativa', () => {
  it.each([
    ['Recebemos seu pagamento. Obrigado!', ''],
    ['Pesquisa de satisfação: avalie seu atendimento', ''],
    ['Você recebeu um Pix de Fulano no valor de R$ 500,00', ''],
    ['Sua compra no valor de R$ 89,90 foi aprovada', ''],
    ['Depósito recebido', ''],
    ['Estorno realizado', ''],
    ['Olá\n\nO pagamento de boleto foi agendado', ''],
    ['Olá', 'Você recebeu um Pix de Fulano'],
  ])('"%s" / assunto "%s" → true', (texto, assunto) => {
    expect(temEvidenciaNegativa(texto, assunto)).toBe(true);
  });
  it('only looks at the first 3 non-empty lines', () => {
    expect(temEvidenciaNegativa('a\nb\nc\nRecebemos seu pagamento', '')).toBe(false);
  });
  it('a pending invoice is not negative', () => {
    expect(temEvidenciaNegativa('Sua fatura já está fechada, vence no dia 15 de setembro', 'A fatura do seu cartão está fechada')).toBe(false);
  });
  it('checks isSettledPaymentSubject on the subject too, not just the first 3 body lines', () => {
    expect(temEvidenciaNegativa('Valor a pagar: R$ 200,00', 'Pagamento da fatura confirmado')).toBe(true);
    expect(temEvidenciaNegativa('Valor a pagar: R$ 200,00', 'Fatura quitada')).toBe(true);
    expect(temEvidenciaNegativa('Valor a pagar: R$ 200,00', 'A fatura do seu cartão está fechada')).toBe(false);
  });
});
