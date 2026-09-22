import { readFileSync } from 'fs';
import { join } from 'path';
import { triagem } from './finance-email-detector';

const amostra = JSON.parse(
  readFileSync(
    join(__dirname, '__fixtures__', 'amostra-real-2026-09.json'),
    'utf-8',
  ),
) as {
  remetente: string;
  assunto: string;
  financeiro: boolean;
}[];
const t = (r: string, a: string, marcado = false) => triagem(r, a, { marcado });

describe('triagem — amostra real', () => {
  it.each(amostra.filter((e) => e.financeiro))(
    '$assunto é candidato',
    ({ remetente, assunto }) => {
      expect(['forte', 'fraco']).toContain(t(remetente, assunto).nivel);
    },
  );
  it.each(amostra.filter((e) => !e.financeiro))(
    '$assunto não é forte',
    ({ remetente, assunto }) => {
      expect(t(remetente, assunto).nivel).not.toBe('forte');
    },
  );
});

describe('triagem — instituições fictícias fora da lista', () => {
  it('Banco Alfa: ciclo próprio → forte (S1a)', () => {
    expect(
      t('Banco Alfa <fatura@bancoalfa.com.br>', 'Sua fatura Alfa Visa fechou')
        .nivel,
    ).toBe('forte');
  });
  it('Coop Beta: boleto sem ciclo → fraco', () => {
    expect(
      t(
        'Coop Beta <contato@coopbeta.coop.br>',
        'Boleto da mensalidade de outubro',
      ).nivel,
    ).toBe('fraco');
  });
  it('Fintech Gama: valor com centavos + vencimento → forte (S8)', () => {
    expect(
      t('Gama <no-reply@gamapay.com>', 'Vencimento amanhã: R$ 89,90'),
    ).toMatchObject({ nivel: 'forte', sinais: ['S8'] });
  });
  it('Loja Delta: sem juros → veto', () => {
    expect(
      t(
        'Loja Delta <ofertas@lojadelta.com.br>',
        'Fatura em 12x sem juros — aproveite',
      ).nivel,
    ).toBe('nao');
  });
});

describe('triagem — sinais fortes', () => {
  it.each([
    [
      'Nubank <todomundo@nubank.com.br>',
      'A fatura do seu cartão Nu Empresas está fechada',
      'S1a',
    ],
    [
      'Santander <faturaporemail@santander.com.br>',
      'Fatura por e-mail - Setembro/2026',
      'S1b',
    ],
    [
      'Neoenergia <cliente@faturaneoenergiabrasilia.com.br>',
      'Fatura Digital 🧾 | 3288653',
      'S1b',
    ],
    [
      'Nubank <todomundo@nubank.com.br>',
      'Novo boleto emitido no seu CPF',
      'S2',
    ],
    ['Loja W <contato@lojaw.com.br>', 'Seu carnê chegou', 'S2'],
    [
      'Porto Consórcio <portoconsorcio@portoseguro.com.br>',
      'Informativo Consórcio Porto Bank',
      'S3',
    ],
    ["Sam's Club <fatura_digital@cartaosamsclub.com.br>", 'Confira!', 'S3'],
    [
      'Nubank <todomundo@nubank.com.br>',
      'Extrato da fatura do Cartão Nubank',
      'S1c',
    ],
    ['Banco X <no-reply@bancox.com.br>', 'Seu extrato de fatura chegou', 'S1c'],
    ['Nubank <todomundo@nubank.com.br>', 'Extrato da sua fatura', 'S1c'],
    [
      'Banco X <no-reply@bancox.com.br>',
      'Fatura do cartão — extrato em anexo',
      'S1c',
    ],
    ['Banco X <no-reply@bancox.com.br>', 'Fatura: extrato disponível', 'S1c'],
  ])('%s / %s → forte por %s', (r, a, sinal) => {
    expect(t(r, a)).toMatchObject({ nivel: 'forte', sinais: [sinal] });
  });
  it('marcador força forte e anula veto', () => {
    expect(
      t(
        'Nubank <todomundo@nubank.com.br>',
        'Extrato da sua conta do Nubank',
        true,
      ),
    ).toMatchObject({ nivel: 'forte', sinais: ['S4'] });
  });
  it('S1a sobrevive a cauda de marketing (veto brando)', () => {
    expect(
      t(
        'Nubank <todomundo@nubank.com.br>',
        'Sua fatura chegou. Saiba como pagar',
      ).nivel,
    ).toBe('forte');
    expect(
      t(
        'Nubank <todomundo@nubank.com.br>',
        'Sua fatura fechou — conheça o Nubank Ultravioleta',
      ).nivel,
    ).toBe('forte');
  });
  it('veto brando derruba S2/S3', () => {
    expect(
      t('Banco Z <contato@bancoz.com.br>', 'Boleto emitido — descubra o app')
        .nivel,
    ).toBe('nao');
  });
  it('assunto em NFD dá o mesmo resultado', () => {
    // NFD explícito: "cartão" e "está" usam aqui os caracteres de combinação
    // Unicode U+0303 (~) e U+0301 (´) logo após a vogal-base, não os precompostos "ã"/"á" — por
    // isso normalize('NFC') muda a string (assert abaixo).
    const assuntoNfd = 'A fatura do seu cartão está fechada';
    expect(assuntoNfd.normalize('NFC')).not.toBe(assuntoNfd);
    expect(assuntoNfd.normalize('NFC')).toBe(
      'A fatura do seu cartão está fechada',
    );
    expect(t('Nubank <todomundo@nubank.com.br>', assuntoNfd).nivel).toBe(
      'forte',
    );
  });
  it('S3/S7 usam o endereço extraído, não o From cru', () => {
    expect(
      t('Pefisa <pagamento@pefisa.com.br>', 'Sua Fatura CELEBRE! ELO MAIS'),
    ).toMatchObject({
      nivel: 'fraco',
      sinais: expect.arrayContaining(['S6', 'S3f']),
    });
  });
});

describe('triagem — S1c (extrato da fatura) não fura os demais vetos', () => {
  const nubank = 'Nubank <todomundo@nubank.com.br>';
  it.each([
    ['veto brando', 'Saiba ler o extrato da sua fatura'],
    ['veto brando', 'Descubra o extrato da fatura digital'],
    ['veto brando', 'Entenda o extrato da sua fatura'],
    ['veto brando', 'Novidades no extrato da fatura'],
    ['veto brando', 'Conheça o novo extrato da fatura'],
    ['veto brando', 'Dica: o extrato da fatura mudou'],
    ['veto brando', 'Aproveite o novo extrato da fatura'],
    ['já paga', 'Extrato da fatura já paga'],
    ['já paga', 'Extrato da fatura anterior, totalmente paga'],
    ['fidelidade', 'Extrato de pontos Livelo para abater na fatura'],
    ['informe de rendimentos', 'Extrato para IR e fatura de 2025'],
    ['informe de rendimentos', 'Extrato de rendimentos da fatura'],
    [
      'informe de rendimentos',
      'Informe de rendimentos: extrato consolidado da fatura anual',
    ],
    ['investimento', 'Extrato do seu investimento e a fatura'],
    ['recompensas', 'Extrato da fatura do programa de recompensas'],
    ['IRPF', 'Extrato da fatura para o IRPF'],
    ['IRPF', 'Extratos das faturas de 2025 — IRPF'],
    ['fidelidade', 'Extrato da fatura Livelo'],
    ['previdência', 'Extrato da fatura da sua previdência privada'],
    ['fundo', 'Extrato da fatura do seu fundo'],
    ['dividendos', 'Extrato da fatura e dos seus dividendos'],
    ['clube', 'Extrato da fatura do seu clube de vantagens'],
    ['conta + marketing', 'Extrato da conta: parcele sua fatura em 12x'],
    [
      'informe de rendimentos',
      'Informe de rendimentos: extrato da fatura anual',
    ],
    [
      'informe de rendimentos',
      'Informe de rendimentos: extrato da fatura 2025',
    ],
    ['IR', 'Extratos das faturas de 2025 para IR'],
    ['IR', 'Extrato da fatura anual para o Imposto de Renda'],
    ['declaração', 'Extrato das faturas do ano para sua declaração'],
    ['rendimentos', 'Extrato da fatura de rendimentos'],
    ['investimento', 'Extrato da fatura do seu investimento'],
    ['pontos', 'Extrato da fatura de pontos Livelo'],
    ['milhas', 'Extrato da fatura: suas milhas do mês'],
  ])('%s: %s → nao', (_motivo, assunto) => {
    expect(t(nubank, assunto).nivel).toBe('nao');
  });
  it('fatura ainda não paga continua sendo cobrança', () => {
    expect(t(nubank, 'Extrato da fatura ainda não paga').nivel).toBe('forte');
  });
  it.each([
    ['A fatura do seu cartão Nubank está fechada. Confira o extrato', 'S1a'],
    ['Sua fatura venceu — veja o extrato no app', 'S1a'],
    ['Sua fatura ainda não foi paga: veja o extrato', 'S1a'],
    ['Boleto disponível: confira também seu extrato', 'S2'],
    ['Fatura por e-mail - Setembro/2026 (extrato anexo)', 'S1b'],
  ])(
    'veto de extrato cede a sinal forte do assunto: %s → %s',
    (assunto, sinal) => {
      expect(t(nubank, assunto)).toMatchObject({
        nivel: 'forte',
        sinais: [sinal],
      });
    },
  );
  it.each([
    'Extrato da fatura vai ir por e-mail',
    'EXTRATO DA FATURA VAI IR POR E-MAIL',
    'Extrato da Fatura — Hora de IR ao app',
  ])('sigla IR sem contexto fiscal não derruba: %s', (assunto) => {
    expect(t(nubank, assunto).nivel).toBe('forte');
  });
  it.each([
    ['Extratos das suas faturas', 'S1c'],
    ['Extrato de suas faturas', 'S1c'],
    ['Extrato das minhas faturas', 'S1c'],
    ['Extrato desta fatura', 'S1c'],
    ['Fatura e extrato do cartão disponíveis no app', 'S1c'],
  ])(
    'S1c aceita plural/possessivo/demonstrativo: %s → %s',
    (assunto, sinal) => {
      expect(t(nubank, assunto)).toMatchObject({
        nivel: 'forte',
        sinais: [sinal],
      });
    },
  );
  it.each([
    'Lembrete: extrato e fatura de outubro',
    'Fatura de outubro e extrato no app',
    'Boleto e extrato de setembro',
    'Extrato e fatura do consórcio de outubro',
    'Extrato bancário e fatura de energia',
  ])(
    'extrato + documento de cobrança sem sinal forte cai em fraco (corpo decide): %s',
    (assunto) => {
      expect(t(nubank, assunto).nivel).toBe('fraco');
    },
  );
  it.each([
    'Entenda o que acontece quando a fatura fica em aberto',
    'Descubra por que sua fatura está em aberto',
    'Saiba o que fazer se a fatura ainda não foi paga',
    'Novidades para quem tem a fatura em aberto',
    'Dica: a fatura em aberto pode ser negociada',
    'Conheça o novo jeito de pagar a fatura em aberto',
    'Aproveite: a fatura ainda não foi paga, negocie agora',
    'Saiba como negociar a fatura em atraso',
  ])(
    'verbo de marketing ANTES do S1a é cabeça, não cauda → nao: %s',
    (assunto) => {
      expect(t(nubank, assunto).nivel).toBe('nao');
    },
  );
  it.each([
    ['Fatura anterior paga. Fatura de outubro disponível', 'fraco'],
    ['Fatura anterior paga: a atual vence dia 10', 'fraco'],
  ])(
    'liquidação de fatura anterior não veta a cobrança vigente: %s → %s',
    (assunto, nivel) => {
      expect(t(nubank, assunto).nivel).toBe(nivel);
    },
  );
  it('tema fiscal anula o "documento de cobrança" (E7 não pode salvar "Informe de rendimentos e sua fatura anual")', () => {
    expect(
      t(nubank, 'Informe de rendimentos e sua fatura anual'),
    ).toMatchObject({
      nivel: 'fraco',
      assuntoTemSubstantivoCobranca: true,
      assuntoTemDocumentoDeCobranca: false,
    });
  });
  it.each([
    'Sua fatura foi paga. A próxima está em aberto',
    'Fatura quitada! A próxima já está em aberto',
    'Fatura anterior paga. A nova fatura ainda não foi paga',
    'Fatura quitada. Boleto de outubro emitido',
    'Fatura, já paga, e a próxima em aberto',
  ])(
    'CICLO acompanha S1a/S2 — cobrança vigente após liquidação não vira nao: %s',
    (assunto) => {
      expect(t(nubank, assunto).nivel).not.toBe('nao');
    },
  );
  it.each([
    'Sua fatura não paga juros no parcelamento',
    'Com a Nu, a fatura não paga tarifa',
    'A fatura não paga anuidade',
  ])(
    '"não paga" como VERBO (juros/tarifa) não é cobrança em aberto: %s',
    (assunto) => {
      expect(t(nubank, assunto).nivel).not.toBe('forte');
    },
  );
  it.each([
    'Extrato da fatura para declarar',
    'Extrato das faturas de 2025 para declarar',
    'Extrato da fatura para a Receita Federal',
    'Extrato da fatura: guarde para declarar',
    'Extrato da fatura para o leão',
  ])('tema fiscal por flexão/sinônimo: %s → nao', (assunto) => {
    expect(t(nubank, assunto).nivel).toBe('nao');
  });
  it.each([
    'Declaração anual: extrato e fatura',
    'Extrato, boleto e informe de rendimentos',
  ])(
    'decisão explícita: tema fiscal VENCE o documento de cobrança → nao (não fraco): %s',
    (assunto) => {
      expect(t(nubank, assunto).nivel).toBe('nao');
    },
  );
  it.each([
    'Sua fatura foi paga: veja o extrato disponível',
    'Sua fatura do cartão está quitada — extrato disponível',
    'Fatura paga: extrato disponível',
    'Fatura quitada, obrigado! Extrato disponível',
    'Comprovante de pagamento: R$ 120,00 - vencimento 05/10/2026',
    'Pagamento confirmado: boleto com vencimento em 05/10',
    'Comprovante de pagamento — fatura com vencimento em 10/10/2026',
    'Pagamento da fatura confirmado, vencimento 10/10',
  ])(
    'recibo com "extrato disponível"/"vencimento" na oração vizinha continua nao: %s',
    (assunto) => {
      expect(t(nubank, assunto).nivel).toBe('nao');
    },
  );
  it.each([
    'Fatura paga - a próxima vence dia 10',
    'Fatura paga (a próxima já está disponível)',
    'Fatura anterior paga / a atual vence dia 10',
    'Pagamento recebido! Nova fatura emitida',
    'Recebemos seu pagamento. Sua fatura de outubro já está disponível',
  ])(
    'separadores completos e vetos por oração — cobrança vigente não vira nao: %s',
    (assunto) => {
      expect(t(nubank, assunto).nivel).not.toBe('nao');
    },
  );
  it('"Parcele sua fatura em 12x" é marketing', () => {
    expect(t(nubank, 'Parcele sua fatura em 12x').nivel).toBe('nao');
  });
  it('assuntoTemDocumentoDeCobranca é mais estreito que o substantivo genérico', () => {
    expect(t(nubank, 'Relatório anual do seu consórcio')).toMatchObject({
      assuntoTemSubstantivoCobranca: true,
      assuntoTemDocumentoDeCobranca: false,
    });
    expect(t(nubank, 'Boleto da mensalidade')).toMatchObject({
      assuntoTemDocumentoDeCobranca: true,
    });
  });
});

describe('triagem — vetos duros', () => {
  it.each([
    'Seu extrato da conta Nu Empresas',
    'Extrato da sua conta do Nubank',
    'Extrato bancário de agosto',
    'O cadastro do seu Débito automático foi cadastrado',
    'Seu recibo de pedido',
    'Seu pedido foi enviado',
    'Pesquisa de satisfação',
    'Convite especial',
    'Ganhe pontos',
    'Sorteio de R$ 100 mil',
    'Cashback liberado',
    'iPhone 18: 50% OFF',
    'Fatura em 12x sem juros',
    'Simule seu financiamento',
    'Empréstimo pré-aprovado',
    'Fatura contestada — estamos analisando',
    'Sua fatura em análise',
    'Disputa aberta',
    'Boleto: como funciona?',
    'Fatura digital: saiba como aderir',
    'Escolha como receber sua conta de luz',
    'Cadastre-se na fatura por e-mail',
    'Adesão à fatura digital',
    'Fatura do mês: prefira o débito automático',
    'Agora você pode pagar boletos',
    'Sua senha vence em 3 dias',
    'Código de verificação: 483920',
    'Código de segurança',
    'Alerta de segurança: novo acesso',
    'Renove seu seguro auto',
    'Sua fatura está disponível: aproveite 20% de desconto',
    'Cupom de R$ 10',
    'Ofertas da semana',
    'Promoção: R$ 20 de desconto vence hoje',
    'Oferta: R$ 0 de anuidade — vence hoje',
    'Pagamento de boleto agendado',
    'Estorno realizado na sua conta',
    'Depósito recebido',
    'Pagamento recebido',
  ])('"%s" → nao', (assunto) => {
    expect(t('Banco Z <contato@bancoz.com.br>', assunto).nivel).toBe('nao');
  });
  it.each([
    'novidades@nubank.com.br',
    'news@email.sualuz.com.br',
    'newsletter@x.com',
    'marketing@x.com',
    'promo@x.com',
    'ofertas@x.com',
    'comunicacao@x.com',
  ])('remetente %s → nao', (end) => {
    expect(t(`X <${end}>`, 'Sua fatura chegou').nivel).toBe('nao');
  });
  it('comprovante de pagamento → nao (settled)', () => {
    expect(
      t('Banco Z <contato@bancoz.com.br>', 'Comprovante de pagamento da fatura')
        .nivel,
    ).toBe('nao');
  });
  it('"Você venceu! Prêmio de R$ 500,00" → nao (veto duro, não S8)', () => {
    expect(
      t('Banco Z <contato@bancoz.com.br>', 'Você venceu! Prêmio de R$ 500,00')
        .nivel,
    ).not.toBe('forte');
    expect(
      t('Banco Z <contato@bancoz.com.br>', 'Você venceu! Prêmio de R$ 500,00')
        .nivel,
    ).toBe('nao');
  });
  it('"Vencimento amanhã: R$ 89,90" continua forte S8 (não pega no veto de prêmio)', () => {
    expect(
      t('Gama <no-reply@gamapay.com>', 'Vencimento amanhã: R$ 89,90'),
    ).toMatchObject({ nivel: 'forte', sinais: ['S8'] });
  });
  it('"Premiação: R$ 500,00 — resgate até o vencimento" → nao (veto duro premiação)', () => {
    expect(
      t(
        'Banco Z <contato@bancoz.com.br>',
        'Premiação: R$ 500,00 — resgate até o vencimento',
      ).nivel,
    ).toBe('nao');
  });
});

describe('triagem — prêmio de seguro não é veto (removido do veto duro)', () => {
  it('"Boleto do prêmio do seguro auto disponível" → forte S2', () => {
    expect(
      t(
        'Seguradora <contato@seguradora.com.br>',
        'Boleto do prêmio do seguro auto disponível',
      ),
    ).toMatchObject({
      nivel: 'forte',
      sinais: ['S2'],
    });
  });
  it('"Prêmio do seguro: R$ 189,90 com vencimento em 10/10" → forte S8', () => {
    expect(
      t(
        'Seguradora <contato@seguradora.com.br>',
        'Prêmio do seguro: R$ 189,90 com vencimento em 10/10',
      ),
    ).toMatchObject({
      nivel: 'forte',
      sinais: ['S8'],
    });
  });
  it('"Pagamento do prêmio — parcela 3/12 vence 10/10" → not nao (fraco S6, sem centavos)', () => {
    expect(
      t(
        'Seguradora <contato@seguradora.com.br>',
        'Pagamento do prêmio — parcela 3/12 vence 10/10',
      ).nivel,
    ).not.toBe('nao');
  });
});

describe('triagem — adversariais de assunto nunca são forte', () => {
  it.each([
    [
      'Google <no-reply@accounts.google.com>',
      'Sua conta Google está pendente de verificação',
    ],
    [
      'Spotify <no-reply@spotify.com>',
      'Sua conta Spotify: nova senha disponível',
    ],
    [
      'Banco Z <contato@bancoz.com.br>',
      'Parcelamento da fatura agora disponível no app',
    ],
    ['Nubank <todomundo@nubank.com.br>', 'Parcele sua fatura em 12x'],
    ['Nubank <todomundo@nubank.com.br>', 'Dica: como entender sua fatura'],
    ['Açougue <contato@acougue.com.br>', 'Carne de primeira toda semana'],
    ['Banco Z <contato@bancoz.com.br>', 'Entenda o que é a linha digitável'],
    ['Escola X <financeiro@escolax.com.br>', 'Reunião de pais'],
    ['Clínica Y <faturamento@clinicay.com.br>', 'Confirmação de agendamento'],
    [
      'Banco Z <contato@bancoz.com.br>',
      'Ganhe R$ 50 de bônus até o vencimento',
    ],
    ['Banco Z <contato@bancoz.com.br>', 'Seu limite subiu para R$ 5.000'],
    ['Nubank <todomundo@nubank.com.br>', 'Pix recebido de Fulano'],
    ['Nubank <todomundo@nubank.com.br>', 'Você recebeu um Pix de Fulano'],
    ['Nubank <todomundo@nubank.com.br>', 'Resumo das suas compras'],
    [
      'Enel <cliente@enel.com.br>',
      'Aviso de interrupção de energia programada',
    ],
    ['Loja <contato@lojafav.com.br>', 'Fatura digital da sua loja favorita'],
    ['SaaS <suporte@saas.com>', 'Sua cobrança foi ajustada'],
    ['RH <rh@empresa.com.br>', 'Prestação de contas — viagem'],
  ])('%s / %s', (r, a) => {
    expect(t(r, a).nivel).not.toBe('forte');
  });
});

describe('triagem — sinais fracos e substantivo de cobrança', () => {
  it.each([
    'Guia IPTU 2026',
    'IPVA disponível',
    'DAS do mês',
    'Sua conta chegou',
    'Sua conta de luz',
    'Seguro auto',
    'Linha digitável do mês',
    'Código de barras atualizado',
    'Cobrança de setembro',
    'Consórcio contemplado',
    'Financiamento aprovado',
    'Empréstimo liberado',
    'Prestação 3',
    'Parcelas do curso',
    'Anuidade 2026',
    'Vencimento hoje',
  ])('"%s" → fraco (S6)', (a) => {
    const r = t('Empresa <contato@empresa-qualquer.com.br>', a);
    expect(r.nivel).toBe('fraco');
    expect(r.sinais).toContain('S6');
  });
  it('DAS minúsculo não é S6', () => {
    expect(
      t('Empresa <contato@empresa-qualquer.com.br>', 'Resumo das compras')
        .sinais,
    ).not.toContain('S6');
  });
  it('S1b sem período e sem veto → fraco', () => {
    expect(
      t('Loja <contato@lojafav.com.br>', 'Fatura digital da sua loja favorita')
        .nivel,
    ).toBe('fraco');
  });
  it.each([
    'leroymerlinpay',
    'faturaneoenergiabrasilia',
    'bancoalfa',
    'gamapay',
    'cartaosamsclub',
    'nubank',
  ])('S7 casa %s', (rotulo) => {
    expect(t(`X <x@${rotulo}.com>`, 'Olá').sinais).toContain('S7');
  });
  it.each(['nomadglobal', 'google', 'spotify', 'gastrobar', 'muffin'])(
    'S7 não casa %s',
    (rotulo) => {
      expect(t(`X <x@${rotulo}.com>`, 'Olá').nivel).toBe('nao');
    },
  );
  it('assuntoTemSubstantivoCobranca reflete S6/S1/S2', () => {
    expect(
      t('X <x@x.com>', 'Fatura da Starlink').assuntoTemSubstantivoCobranca,
    ).toBe(true);
    expect(t('X <x@nubank.com.br>', 'Olá').assuntoTemSubstantivoCobranca).toBe(
      false,
    );
  });
  it('"Seu carnê chegou" também marca assuntoTemSubstantivoCobranca', () => {
    expect(
      t('X <x@x.com>', 'Seu carnê chegou').assuntoTemSubstantivoCobranca,
    ).toBe(true);
  });
});

describe('triagem — venc(e|eu|ido|ida|imento|imentos) não é prefixo aberto', () => {
  it('"vencedor" não é S8 (prefixo "venc" sem ser flexão de vencimento)', () => {
    const r = t(
      'Promo <contato@bancoz.com.br>',
      'Parabéns! Você é o vencedor de R$ 1.000,00',
    );
    expect(r.nivel).not.toBe('forte');
    expect(r.sinais).not.toContain('S8');
  });
  it('"Vencimento amanhã: R$ 89,90" continua forte S8', () => {
    expect(
      t('Gama <no-reply@gamapay.com>', 'Vencimento amanhã: R$ 89,90'),
    ).toMatchObject({ nivel: 'forte', sinais: ['S8'] });
  });
  it('"Novo boleto emitido no seu CPF" continua forte S2', () => {
    expect(
      t('Nubank <todomundo@nubank.com.br>', 'Novo boleto emitido no seu CPF'),
    ).toMatchObject({ nivel: 'forte', sinais: ['S2'] });
  });
  it('"Boleto vence hoje" é forte S2', () => {
    expect(
      t('Banco Z <contato@bancoz.com.br>', 'Boleto vence hoje'),
    ).toMatchObject({ nivel: 'forte', sinais: ['S2'] });
  });
});

describe('triagem — "sua conta … chegou/disponível/vence" (S6 fraco)', () => {
  it.each([
    'Sua conta Vivo chegou',
    'Chegou sua conta Vivo de setembro',
    'Sua conta Claro está disponível',
  ])('"%s" → fraco com S6', (assunto) => {
    const r = t('Empresa <contato@empresa-qualquer.com.br>', assunto);
    expect(r.nivel).toBe('fraco');
    expect(r.sinais).toContain('S6');
  });
  it('"Sua conta Google está pendente de verificação" continua não forte', () => {
    expect(
      t(
        'Google <no-reply@accounts.google.com>',
        'Sua conta Google está pendente de verificação',
      ).nivel,
    ).not.toBe('forte');
  });
});

describe('triagem — vetos brandos: desconto e adesão não anulam sinal forte', () => {
  it('"Sua fatura chegou com desconto por pagamento antecipado" é forte S1a', () => {
    expect(
      t(
        'Banco Z <contato@bancoz.com.br>',
        'Sua fatura chegou com desconto por pagamento antecipado',
      ),
    ).toMatchObject({ nivel: 'forte', sinais: ['S1a'] });
  });
  it('"Promoção: R$ 20 de desconto vence hoje" continua nao (veto duro promoção)', () => {
    expect(
      t(
        'Banco Z <contato@bancoz.com.br>',
        'Promoção: R$ 20 de desconto vence hoje',
      ).nivel,
    ).toBe('nao');
  });
  it('"Taxa de adesão — boleto disponível" é forte S2 (adesão é veto brando, não duro)', () => {
    expect(
      t(
        'Banco Z <contato@bancoz.com.br>',
        'Taxa de adesão — boleto disponível',
      ),
    ).toMatchObject({
      nivel: 'forte',
      sinais: ['S2'],
    });
  });
  it('"Fatura digital: saiba como aderir" continua nao (veto duro "como aderir")', () => {
    expect(
      t('Banco Z <contato@bancoz.com.br>', 'Fatura digital: saiba como aderir')
        .nivel,
    ).toBe('nao');
  });
  it('"Adesão à fatura digital" continua nao (sem sinal forte, veto brando tardio)', () => {
    expect(
      t('Banco Z <contato@bancoz.com.br>', 'Adesão à fatura digital').nivel,
    ).toBe('nao');
  });
  it('"Boleto disponível com desconto até dia 5" é forte S2 (desconto é tardio, não normal)', () => {
    expect(
      t(
        'Banco Z <contato@bancoz.com.br>',
        'Boleto disponível com desconto até dia 5',
      ),
    ).toMatchObject({
      nivel: 'forte',
      sinais: ['S2'],
    });
  });
  it('"Fatura disponível com desconto por pagamento antecipado" não é nao (verbo de ciclo "disponível" isenta o veto tardio)', () => {
    expect(
      t(
        'Banco Z <contato@bancoz.com.br>',
        'Fatura disponível com desconto por pagamento antecipado',
      ).nivel,
    ).not.toBe('nao');
  });
  it('"Parcele sua fatura com desconto" continua nao (sem verbo de ciclo, veto brando tardio)', () => {
    expect(
      t('Banco Z <contato@bancoz.com.br>', 'Parcele sua fatura com desconto')
        .nivel,
    ).toBe('nao');
  });
  it('"Antecipe parcelas da sua fatura com desconto" continua nao (sem verbo de ciclo, veto brando tardio)', () => {
    expect(
      t(
        'Banco Z <contato@bancoz.com.br>',
        'Antecipe parcelas da sua fatura com desconto',
      ).nivel,
    ).toBe('nao');
  });
  it('"Mensalidade de outubro vence dia 5 com desconto" não é nao (verbo de ciclo "vence" em qualquer posição isenta o veto)', () => {
    expect(
      t(
        'Banco Z <contato@bancoz.com.br>',
        'Mensalidade de outubro vence dia 5 com desconto',
      ).nivel,
    ).not.toBe('nao');
  });
  it('"Fatura gerada com desconto por pagamento antecipado" não é nao (verbo de ciclo "gerada")', () => {
    expect(
      t(
        'Banco Z <contato@bancoz.com.br>',
        'Fatura gerada com desconto por pagamento antecipado',
      ).nivel,
    ).not.toBe('nao');
  });
  it('"Pague com desconto: fatura disponível" não é nao (verbo de ciclo "disponível" em qualquer posição, não só antes de "desconto")', () => {
    expect(
      t(
        'Banco Z <contato@bancoz.com.br>',
        'Pague com desconto: fatura disponível',
      ).nivel,
    ).not.toBe('nao');
  });
  it('"Sua fatura está disponível: aproveite 20% de desconto" continua nao (veto duro "% de desconto")', () => {
    expect(
      t(
        'Banco Z <contato@bancoz.com.br>',
        'Sua fatura está disponível: aproveite 20% de desconto',
      ).nivel,
    ).toBe('nao');
  });
});

describe('triagem — flexão de venc ampliada (vence/vencem/vencendo/vencerá/vencidos)', () => {
  it.each([
    'Boletos vencem amanhã',
    'Boletos vencidos — regularize',
    'Boleto vencendo hoje',
    'Boleto vencerá em 3 dias',
  ])('"%s" → forte S2', (assunto) => {
    expect(t('Banco Z <contato@bancoz.com.br>', assunto)).toMatchObject({
      nivel: 'forte',
      sinais: ['S2'],
    });
  });
  it('"Parcelas vencem dia 10: R$ 350,00" → forte S8 (venc + centavos)', () => {
    expect(
      t('Banco Z <contato@bancoz.com.br>', 'Parcelas vencem dia 10: R$ 350,00'),
    ).toMatchObject({
      nivel: 'forte',
      sinais: ['S8'],
    });
  });
  it('"vencedor" continua não sendo flexão de vencimento', () => {
    const r = t(
      'Promo <contato@bancoz.com.br>',
      'Parabéns! Você é o vencedor de R$ 1.000,00',
    );
    expect(r.nivel).not.toBe('forte');
    expect(r.sinais).not.toContain('S8');
  });
});

describe('triagem — veto duro de recibo/pagamento em inglês', () => {
  it('"Your receipt from SaaS" (invoice@) → nao', () => {
    expect(t('SaaS <invoice@saas.com>', 'Your receipt from SaaS').nivel).toBe(
      'nao',
    );
  });
  it('"Payment received — thank you" → nao', () => {
    expect(
      t('SaaS <invoice@saas.com>', 'Payment received — thank you').nivel,
    ).toBe('nao');
  });
  it('"Your invoice is ready" (invoice@) continua forte S3', () => {
    expect(t('SaaS <invoice@saas.com>', 'Your invoice is ready')).toMatchObject(
      { nivel: 'forte', sinais: ['S3'] },
    );
  });
});

describe('triagem — veto de remetente "promo" ancorado', () => {
  it.each([
    'contato@compromovel.com.br',
    'atendimento@promotoracredito.com.br',
  ])('%s não é falso positivo de "promo" → forte por S1a', (endereco) => {
    expect(t(`X <${endereco}>`, 'Sua fatura chegou').nivel).toBe('forte');
  });
  it.each([
    'promo@x.com',
    'promo.x@y.com',
    'x@promo.bancoz.com.br',
    'promocoes@x.com',
    'todomundo@promocoes.nubank.com.br',
    'promocoes.x@y.com',
    'x@promocional.loja.com.br',
  ])(
    'remetente %s → nao (forma derivada de "promo" em qualquer posição)',
    (endereco) => {
      expect(t(`X <${endereco}>`, 'Sua fatura chegou').nivel).toBe('nao');
    },
  );
});
