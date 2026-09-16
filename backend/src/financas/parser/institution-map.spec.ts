import { resolverInstituicao, UTILIDADE_RE } from './institution-map';

describe('resolverInstituicao', () => {
  it('matches by domain suffix, covering subdomains', () => {
    expect(resolverInstituicao('Leroy <noreply@leroymerlinpay.pefisa.com.br>', '')).toEqual({
      nome: 'Pefisa',
      tipoPadrao: 'CARTAO',
      mapeada: true,
    });
    expect(resolverInstituicao('x@faturaneoenergiabrasilia.com.br', '')).toEqual({
      nome: 'Neoenergia',
      tipoPadrao: 'OUTRO',
      mapeada: true,
    });
  });

  it('does not match a look-alike domain', () => {
    expect(resolverInstituicao('x@nubank.com.br.evil.com', '').mapeada).toBe(false);
  });

  it('derives a name for an unknown institution and leaves tipo undefined', () => {
    expect(resolverInstituicao('Banco Alfa <fatura@bancoalfa.com.br>', 'Sua fatura fechou')).toEqual({
      nome: 'Bancoalfa',
      tipoPadrao: undefined,
      mapeada: false,
    });
  });

  it('infers OUTRO for an unknown utility by domain radical or "conta de" subject', () => {
    expect(resolverInstituicao('avisos@energiaxyz.com.br', 'Sua conta chegou').tipoPadrao).toBe('OUTRO');
    expect(resolverInstituicao('contato@fornecedora.com.br', 'Sua conta de luz chegou').tipoPadrao).toBe('OUTRO');
  });

  it('UTILIDADE_RE does not match gastrobar or netflix', () => {
    expect(UTILIDADE_RE.test('gastrobar')).toBe(false);
    expect(UTILIDADE_RE.test('netflix')).toBe(false);
    expect(UTILIDADE_RE.test('neoenergia')).toBe(true);
    expect(UTILIDADE_RE.test('comgas')).toBe(true);
  });

  it('falls back to "Desconhecida" without an address', () => {
    expect(resolverInstituicao('Fulano', '').nome).toBe('Desconhecida');
  });

  it.each([
    ['Banco do Brasil <a@bb.com.br>', 'Banco do Brasil', 'CARTAO'],
    ['Caixa <a@caixa.gov.br>', 'Caixa', 'CARTAO'],
    ['Santander <a@santander.com.br>', 'Santander', 'CARTAO'],
    ['Itaú <a@itau.com.br>', 'Itaú', 'CARTAO'],
    ['Itaú <a@itaucard.com.br>', 'Itaú', 'CARTAO'],
    ['Bradesco <a@bradesco.com.br>', 'Bradesco', 'CARTAO'],
    ['Nubank <a@nubank.com.br>', 'Nubank', 'CARTAO'],
    ['Inter <a@bancointer.com.br>', 'Inter', 'CARTAO'],
    ['C6 <a@c6bank.com.br>', 'C6 Bank', 'CARTAO'],
    ['BTG <a@btgpactual.com>', 'BTG Pactual', 'CARTAO'],
    ['Neon <a@neon.com.br>', 'Neon', 'CARTAO'],
    ['PicPay <a@picpay.com>', 'PicPay', 'CARTAO'],
    ['Mercado Pago <a@mercadopago.com.br>', 'Mercado Pago', 'CARTAO'],
    ['PagBank <a@pagseguro.com.br>', 'PagBank', 'CARTAO'],
    ['Will <a@willbank.com.br>', 'Will Bank', 'CARTAO'],
    ['XP <a@xpi.com.br>', 'XP', 'CARTAO'],
    ['Sicoob <a@sicoob.com.br>', 'Sicoob', 'CARTAO'],
    ['Sicredi <a@sicredi.com.br>', 'Sicredi', 'CARTAO'],
    ['BRB <a@brb.com.br>', 'BRB', 'CARTAO'],
    ['Pan <a@bancopan.com.br>', 'Banco Pan', 'CARTAO'],
    ['BMG <a@bancobmg.com.br>', 'BMG', 'CARTAO'],
    ['Pefisa <a@pefisa.com.br>', 'Pefisa', 'CARTAO'],
    ["Sam's Club <a@cartaosamsclub.com.br>", "Sam's Club", 'CARTAO'],
    ['Midway <a@midway.com.br>', 'Midway', 'CARTAO'],
    ['Claro <a@claro.com.br>', 'Claro', 'OUTRO'],
    ['Vivo <a@vivo.com.br>', 'Vivo', 'OUTRO'],
    ['TIM <a@tim.com.br>', 'TIM', 'OUTRO'],
    ['Enel <a@enel.com.br>', 'Enel', 'OUTRO'],
    ['Neoenergia <a@neoenergiabrasilia.com.br>', 'Neoenergia', 'OUTRO'],
    ['Neoenergia <a@faturaneoenergiabrasilia.com.br>', 'Neoenergia', 'OUTRO'],
    ['Light <a@light.com.br>', 'Light', 'OUTRO'],
    ['CPFL <a@cpfl.com.br>', 'CPFL', 'OUTRO'],
    ['Cemig <a@cemig.com.br>', 'Cemig', 'OUTRO'],
    ['Sabesp <a@sabesp.com.br>', 'Sabesp', 'OUTRO'],
    ['Comgás <a@comgas.com.br>', 'Comgás', 'OUTRO'],
    ['Starlink <a@starlink.com>', 'Starlink', 'OUTRO'],
    ['Porto Seguro <a@portoseguro.com.br>', 'Porto Seguro', 'OUTRO'],
  ])('%s resolves to %s (%s)', (remetente, nomeEsperado, tipoEsperado) => {
    const resultado = resolverInstituicao(remetente, '');
    expect(resultado.mapeada).toBe(true);
    expect(resultado.nome).toBe(nomeEsperado);
    expect(resultado.tipoPadrao).toBe(tipoEsperado);
  });
});
