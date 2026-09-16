import { normalizar, wb } from './text-match.util';

describe('wb', () => {
  it('matches accented words as whole words (JS \\b would fail)', () => {
    expect(wb('\\bcarn[êe]\\b').test('seu carnê chegou')).toBe(true);
    expect(wb('\\bcarn[êe]\\b').test('carne de primeira')).toBe(false);
  });
  it('does not match inside a longer word', () => {
    expect(wb('\\b(sua|a)\\s+fatura\\b').test('parcelamento da fatura disponível')).toBe(false);
    expect(wb('\\b(sua|a)\\s+fatura\\b').test('a fatura do seu cartão')).toBe(true);
  });
  it('is case-insensitive by default and accepts explicit flags', () => {
    expect(wb('\\bDAS\\b').test('resumo das compras')).toBe(true);
    expect(wb('\\bDAS\\b', 'u').test('resumo das compras')).toBe(false);
    expect(wb('\\bDAS\\b', 'u').test('guia DAS emitida')).toBe(true);
  });
  it('treats venc. with the dot as a whole word', () => {
    expect(wb('\\bvenc\\.').test('Venc. 10/10/2026')).toBe(true);
  });
});

describe('normalizar', () => {
  it('normalizes NFD to NFC and tolerates null', () => {
    expect(normalizar('cartão')).toBe('cartão');
    expect(normalizar(null)).toBe('');
  });
});
