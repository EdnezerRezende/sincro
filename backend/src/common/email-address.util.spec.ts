import {
  dominio,
  extrairEndereco,
  localPart,
  rotulosDominio,
} from './email-address.util';

describe('email-address.util', () => {
  it('extracts the address from a display-name header, lowercased', () => {
    expect(extrairEndereco('Pefisa <Pagamento@Pefisa.com.br>')).toBe(
      'pagamento@pefisa.com.br',
    );
    expect(extrairEndereco('todomundo@nubank.com.br')).toBe(
      'todomundo@nubank.com.br',
    );
    expect(extrairEndereco('"Nome <a@b.com> (não responda)"')).toBe('a@b.com');
  });
  it('picks the angle-bracket group that contains @ when there are several', () => {
    expect(extrairEndereco('"<<Promo>>" <promo@x.com>')).toBe('promo@x.com');
  });
  it('returns null when there is no address', () => {
    expect(extrairEndereco('Fulano de Tal')).toBeNull();
    expect(extrairEndereco('a@b')).toBeNull();
  });
  it('falls back to scanning the whole string when the angle group is unclosed', () => {
    expect(extrairEndereco('Nome <a@b.com')).toBe('a@b.com');
  });
  it('splits local part, domain and labels', () => {
    expect(localPart('fatura_digital@cartaosamsclub.com.br')).toBe(
      'fatura_digital',
    );
    expect(dominio('x@leroymerlinpay.pefisa.com.br')).toBe(
      'leroymerlinpay.pefisa.com.br',
    );
    expect(rotulosDominio('x@mail.nubank.com.br')).toEqual([
      'mail',
      'nubank',
      'com',
      'br',
    ]);
  });
});
