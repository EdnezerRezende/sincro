import { normalizar, wb } from './text-match.util';

describe('wb', () => {
  it('matches accented words as whole words (JS \\b would fail)', () => {
    expect(wb('\\bcarnê\\b').test('seu carnê chegou')).toBe(true);
    expect(wb('\\bcarnê\\b').test('carne de primeira')).toBe(false);
  });
  it('does not match inside a longer word', () => {
    expect(
      wb('\\b(sua|a)\\s+fatura\\b').test('parcelamento da fatura disponível'),
    ).toBe(false);
    expect(wb('\\b(sua|a)\\s+fatura\\b').test('a fatura do seu cartão')).toBe(
      true,
    );
  });
  it('is case-insensitive by default and accepts explicit flags', () => {
    expect(wb('\\bDAS\\b').test('resumo das compras')).toBe(true);
    expect(wb('\\bDAS\\b', 'u').test('resumo das compras')).toBe(false);
    expect(wb('\\bDAS\\b', 'u').test('guia DAS emitida')).toBe(true);
  });
  it('treats venc. with the dot as a whole word', () => {
    expect(wb('\\bvenc\\.').test('Venc. 10/10/2026')).toBe(true);
  });
  it('does not depend on the occurrence parity of \\b (odd count, last branch starts with \\b)', () => {
    const re = wb('\\bcontestad|contesta[çc][ãa]o|em an[áa]lise|\\bdisputa\\b');
    expect(re.test('abrimos uma disputa')).toBe(true);
    expect(re.test('disputa aberta')).toBe(true);
  });
  it('matches \\b right after a digit', () => {
    expect(wb('(\\d{1,2})\\b').test('vence dia 10')).toBe(true);
    expect(wb('dia (\\d{1,2})\\b').test('dia 10')).toBe(true);
  });
  it('matches every alternative in a joined \\b-prefixed pattern regardless of position', () => {
    const re = wb(['\\bvenc', '\\bganhe\\b', '\\bsorteio\\b'].join('|'));
    expect(re.test('ganhe pontos')).toBe(true);
    expect(re.test('sorteio hoje')).toBe(true);
    expect(re.test('convencer')).toBe(false);
  });
});

describe('normalizar', () => {
  it('normalizes NFD to NFC and tolerates null', () => {
    expect(normalizar('cartão')).toBe('cartão');
    expect(normalizar(null)).toBe('');
  });
});
