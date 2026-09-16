import { readFileSync } from 'fs';
import { join } from 'path';
import { triagem } from './finance-email-detector';

const amostra = JSON.parse(readFileSync(join(__dirname, '__fixtures__', 'amostra-real-2026-09.json'), 'utf-8')) as {
  remetente: string; assunto: string; financeiro: boolean;
}[];
const t = (r: string, a: string, marcado = false) => triagem(r, a, { marcado });

describe('triagem — amostra real', () => {
  it.each(amostra.filter((e) => e.financeiro))('$assunto é candidato', ({ remetente, assunto }) => {
    expect(['forte', 'fraco']).toContain(t(remetente, assunto).nivel);
  });
  it.each(amostra.filter((e) => !e.financeiro))('$assunto não é forte', ({ remetente, assunto }) => {
    expect(t(remetente, assunto).nivel).not.toBe('forte');
  });
});

describe('triagem — instituições fictícias fora da lista', () => {
  it('Banco Alfa: ciclo próprio → forte (S1a)', () => {
    expect(t('Banco Alfa <fatura@bancoalfa.com.br>', 'Sua fatura Alfa Visa fechou').nivel).toBe('forte');
  });
  it('Coop Beta: boleto sem ciclo → fraco', () => {
    expect(t('Coop Beta <contato@coopbeta.coop.br>', 'Boleto da mensalidade de outubro').nivel).toBe('fraco');
  });
  it('Fintech Gama: valor com centavos + vencimento → forte (S8)', () => {
    expect(t('Gama <no-reply@gamapay.com>', 'Vencimento amanhã: R$ 89,90')).toMatchObject({ nivel: 'forte', sinais: ['S8'] });
  });
  it('Loja Delta: sem juros → veto', () => {
    expect(t('Loja Delta <ofertas@lojadelta.com.br>', 'Fatura em 12x sem juros — aproveite').nivel).toBe('nao');
  });
});

describe('triagem — sinais fortes', () => {
  it.each([
    ['Nubank <todomundo@nubank.com.br>', 'A fatura do seu cartão Nu Empresas está fechada', 'S1a'],
    ['Santander <faturaporemail@santander.com.br>', 'Fatura por e-mail - Setembro/2026', 'S1b'],
    ['Neoenergia <cliente@faturaneoenergiabrasilia.com.br>', 'Fatura Digital 🧾 | 3288653', 'S1b'],
    ['Nubank <todomundo@nubank.com.br>', 'Novo boleto emitido no seu CPF', 'S2'],
    ['Loja W <contato@lojaw.com.br>', 'Seu carnê chegou', 'S2'],
    ['Porto Consórcio <portoconsorcio@portoseguro.com.br>', 'Informativo Consórcio Porto Bank', 'S3'],
    ['Sam\'s Club <fatura_digital@cartaosamsclub.com.br>', 'Confira!', 'S3'],
  ])('%s / %s → forte por %s', (r, a, sinal) => {
    expect(t(r, a)).toMatchObject({ nivel: 'forte', sinais: [sinal] });
  });
  it('marcador força forte e anula veto', () => {
    expect(t('Nubank <todomundo@nubank.com.br>', 'Extrato da sua conta do Nubank', true)).toMatchObject({ nivel: 'forte', sinais: ['S4'] });
  });
  it('S1a sobrevive a cauda de marketing (veto brando)', () => {
    expect(t('Nubank <todomundo@nubank.com.br>', 'Sua fatura chegou. Saiba como pagar').nivel).toBe('forte');
    expect(t('Nubank <todomundo@nubank.com.br>', 'Sua fatura fechou — conheça o Nubank Ultravioleta').nivel).toBe('forte');
  });
  it('veto brando derruba S2/S3', () => {
    expect(t('Banco Z <contato@bancoz.com.br>', 'Boleto emitido — descubra o app').nivel).toBe('nao');
  });
  it('assunto em NFD dá o mesmo resultado', () => {
    expect(t('Nubank <todomundo@nubank.com.br>', 'A fatura do seu cartão está fechada').nivel).toBe('forte');
  });
  it('S3/S7 usam o endereço extraído, não o From cru', () => {
    expect(t('Pefisa <pagamento@pefisa.com.br>', 'Sua Fatura CELEBRE! ELO MAIS')).toMatchObject({ nivel: 'fraco', sinais: expect.arrayContaining(['S6', 'S3f']) });
  });
});

describe('triagem — vetos duros', () => {
  it.each([
    'Seu extrato da conta Nu Empresas', 'O cadastro do seu Débito automático foi cadastrado', 'Seu recibo de pedido',
    'Seu pedido foi enviado', 'Pesquisa de satisfação', 'Convite especial', 'Ganhe pontos', 'Sorteio de R$ 100 mil',
    'Cashback liberado', 'iPhone 18: 50% OFF', 'Fatura em 12x sem juros', 'Simule seu financiamento', 'Empréstimo pré-aprovado',
    'Fatura contestada — estamos analisando', 'Sua fatura em análise', 'Disputa aberta', 'Boleto: como funciona?',
    'Fatura digital: saiba como aderir', 'Escolha como receber sua conta de luz', 'Cadastre-se na fatura por e-mail',
    'Adesão à fatura digital', 'Fatura do mês: prefira o débito automático', 'Agora você pode pagar boletos',
    'Sua senha vence em 3 dias', 'Código de verificação: 483920', 'Código de segurança', 'Alerta de segurança: novo acesso',
    'Renove seu seguro auto', 'Sua fatura está disponível: aproveite 20% de desconto', 'Cupom de R$ 10', 'Ofertas da semana',
    'Promoção: R$ 20 de desconto vence hoje', 'Oferta: R$ 0 de anuidade — vence hoje', 'Pagamento de boleto agendado',
    'Estorno realizado na sua conta', 'Depósito recebido', 'Pagamento recebido',
  ])('"%s" → nao', (assunto) => {
    expect(t('Banco Z <contato@bancoz.com.br>', assunto).nivel).toBe('nao');
  });
  it.each(['novidades@nubank.com.br', 'news@email.sualuz.com.br', 'newsletter@x.com', 'marketing@x.com', 'promo@x.com', 'ofertas@x.com', 'comunicacao@x.com'])(
    'remetente %s → nao', (end) => { expect(t(`X <${end}>`, 'Sua fatura chegou').nivel).toBe('nao'); },
  );
  it('comprovante de pagamento → nao (settled)', () => {
    expect(t('Banco Z <contato@bancoz.com.br>', 'Comprovante de pagamento da fatura').nivel).toBe('nao');
  });
});

describe('triagem — adversariais de assunto nunca são forte', () => {
  it.each([
    ['Google <no-reply@accounts.google.com>', 'Sua conta Google está pendente de verificação'],
    ['Spotify <no-reply@spotify.com>', 'Sua conta Spotify: nova senha disponível'],
    ['Banco Z <contato@bancoz.com.br>', 'Parcelamento da fatura agora disponível no app'],
    ['Nubank <todomundo@nubank.com.br>', 'Parcele sua fatura em 12x'],
    ['Nubank <todomundo@nubank.com.br>', 'Dica: como entender sua fatura'],
    ['Açougue <contato@acougue.com.br>', 'Carne de primeira toda semana'],
    ['Banco Z <contato@bancoz.com.br>', 'Entenda o que é a linha digitável'],
    ['Escola X <financeiro@escolax.com.br>', 'Reunião de pais'],
    ['Clínica Y <faturamento@clinicay.com.br>', 'Confirmação de agendamento'],
    ['Banco Z <contato@bancoz.com.br>', 'Ganhe R$ 50 de bônus até o vencimento'],
    ['Banco Z <contato@bancoz.com.br>', 'Seu limite subiu para R$ 5.000'],
    ['Nubank <todomundo@nubank.com.br>', 'Pix recebido de Fulano'],
    ['Nubank <todomundo@nubank.com.br>', 'Você recebeu um Pix de Fulano'],
    ['Nubank <todomundo@nubank.com.br>', 'Resumo das suas compras'],
    ['Enel <cliente@enel.com.br>', 'Aviso de interrupção de energia programada'],
    ['Loja <contato@lojafav.com.br>', 'Fatura digital da sua loja favorita'],
    ['SaaS <suporte@saas.com>', 'Sua cobrança foi ajustada'],
    ['RH <rh@empresa.com.br>', 'Prestação de contas — viagem'],
  ])('%s / %s', (r, a) => {
    expect(t(r, a).nivel).not.toBe('forte');
  });
});

describe('triagem — sinais fracos e substantivo de cobrança', () => {
  it.each(['Guia IPTU 2026', 'IPVA disponível', 'DAS do mês', 'Sua conta chegou', 'Sua conta de luz', 'Seguro auto', 'Linha digitável do mês', 'Código de barras atualizado', 'Cobrança de setembro', 'Consórcio contemplado', 'Financiamento aprovado', 'Empréstimo liberado', 'Prestação 3', 'Parcelas do curso', 'Anuidade 2026', 'Vencimento hoje'])(
    '"%s" → fraco (S6)', (a) => {
      const r = t('Empresa <contato@empresa-qualquer.com.br>', a);
      expect(r.nivel).toBe('fraco');
      expect(r.sinais).toContain('S6');
    },
  );
  it('DAS minúsculo não é S6', () => {
    expect(t('Empresa <contato@empresa-qualquer.com.br>', 'Resumo das compras').sinais).not.toContain('S6');
  });
  it('S1b sem período e sem veto → fraco', () => {
    expect(t('Loja <contato@lojafav.com.br>', 'Fatura digital da sua loja favorita').nivel).toBe('fraco');
  });
  it.each(['leroymerlinpay', 'faturaneoenergiabrasilia', 'bancoalfa', 'gamapay', 'cartaosamsclub', 'nubank'])('S7 casa %s', (rotulo) => {
    expect(t(`X <x@${rotulo}.com>`, 'Olá').sinais).toContain('S7');
  });
  it.each(['nomadglobal', 'google', 'spotify', 'gastrobar', 'muffin'])('S7 não casa %s', (rotulo) => {
    expect(t(`X <x@${rotulo}.com>`, 'Olá').nivel).toBe('nao');
  });
  it('assuntoTemSubstantivoCobranca reflete S6/S1/S2', () => {
    expect(t('X <x@x.com>', 'Fatura da Starlink').assuntoTemSubstantivoCobranca).toBe(true);
    expect(t('X <x@nubank.com.br>', 'Olá').assuntoTemSubstantivoCobranca).toBe(false);
  });
});
