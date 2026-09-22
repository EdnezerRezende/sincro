import {
  extrairEndereco,
  localPart,
  rotulosDominio,
} from '../../common/email-address.util';
import { normalizar, wb } from '../../common/text-match.util';
import {
  hasActiveBillingClause,
  isSettledWithoutActiveBilling,
} from './invoice-subject-patterns';

export type NivelTriagem = 'nao' | 'forte' | 'fraco';
export interface ResultadoTriagem {
  nivel: NivelTriagem;
  sinais: string[];
  motivo: string | null;
  assuntoTemSubstantivoCobranca: boolean;
  /** Assunto nomeia um DOCUMENTO de cobrança (fatura/boleto/carnê/cobrança/mensalidade) — mais
   *  estreito que o substantivo genérico (consórcio, seguro, parcela...), usado para deixar E7
   *  (planilha anexa) contar como evidência. */
  assuntoTemDocumentoDeCobranca: boolean;
  /** Tema fiscal/fidelidade/investimento no assunto: nenhuma evidência de nome de anexo (E6/E7)
   *  pode gerar lançamento. */
  assuntoTemTemaNaoCobranca: boolean;
}

const VENC_FLEXAO = 'venc(?:e|em|eu|endo|er[áa]|id[oa]s?|imentos?)\\b';

// ---------- Vetos ----------
/** Duros: nunca criam lançamento, nem com S1a. Marketing, segurança, pagamento já feito, movimentações
 *  que NÃO são cobrança (pix/depósito/estorno recebido, agendado). */
/** Cada veto leva um rótulo curto: é ele (não o fonte da regex) que vai para o `motivo` da
 *  triagem e daí para a linha de auditoria do FinanceEmailProcessor. */
interface Veto {
  rotulo: string;
  re: RegExp;
}
const veto = (rotulo: string, re: RegExp): Veto => ({ rotulo, re });
const VETO_EXTRATO = veto('extrato', wb('\\bextratos?\\b'));
const VETOS_POR_ORACAO = new Set(['recebido', 'estorno', 'agendado']);
const VETOS_DUROS: Veto[] = [
  // "Extrato da conta"/"extrato bancário" é movimentação, não cobrança. A única exceção é o
  // extrato DA FATURA (ver `S1C`/`VETO_EXTRATO` em `triagem`): aí o veto cede.
  VETO_EXTRATO,
  veto(
    'debito-automatico-confirmado',
    wb('d[eé]bito autom[aá]tico .{0,30}(conclu[ií]d|cadastrad|ativad)'),
  ),
  veto('recibo-de-pedido', wb('recibo de pedido')),
  veto(
    'pedido-faturado-enviado',
    wb('pedido .{0,20}(faturado|enviado|entregue)'),
  ),
  veto('seu-pedido', wb('\\bseu pedido\\b')),
  veto('pesquisa', wb('\\bpesquisa\\b')),
  veto('convite', wb('\\bconvite\\b')),
  veto('ganhe', wb('\\bganhe\\b')),
  veto('sorteio', wb('\\bsorteio\\b')),
  veto('cashback', wb('\\bcashback\\b')),
  veto('percentual-off', wb('\\d+ ?% ?(off|de desconto)')),
  veto('sem-juros', wb('\\bsem juros\\b')),
  veto('simule', wb('\\bsimule\\b')),
  veto('pre-aprovado', wb('pr[ée]-aprovad')),
  veto('contestado', wb('\\bcontestad')),
  veto('contestacao', wb('contesta[çc][ãa]o')),
  veto('em-analise', wb('em an[áa]lise')),
  veto('disputa', wb('\\bdisputa\\b')),
  veto('como-funciona', wb('\\bcomo (funciona|aderir|receber)\\b')),
  veto('cadastre-se', wb('cadastre-se')),
  veto('prefira', wb('\\bprefira\\b')),
  veto('agora-voce-pode', wb('\\bagora voc[êe] pode\\b')),
  veto('senha', wb('\\bsenha\\b')),
  veto(
    'codigo-de-verificacao',
    wb('\\bc[óo]digo de (verifica[çc][ãa]o|seguran[çc]a|acesso)\\b'),
  ),
  veto('alerta-de-seguranca', wb('\\balerta de seguran[çc]a\\b')),
  veto('renove', wb('\\brenove\\b')),
  veto('cupom', wb('\\bcupom\\b')),
  veto('oferta', wb('\\bofertas?\\b')),
  veto('promocao', wb('promo[çc][ãa]o')),
  veto('agendado', wb('\\bagendad[oa]\\b')),
  veto('estorno', wb('\\bestorno\\b')),
  veto('recebido', wb('\\brecebid[oa]\\b')),
  veto(
    'receipt-paid-en',
    wb('\\b(receipt|paid|payment (received|successful|confirmed))\\b'),
  ),
  veto(
    'parabens-premiacao',
    wb('\\bparab[ée]ns\\b|\\bpremia[çc][ãa]o\\b|\\bvoc[êe] venceu\\b'),
  ),
];
/** Brandos: cauda de marketing num aviso legítimo ("Sua fatura chegou. Saiba como pagar") não o anula —
 *  só derrubam quando S1a NÃO casa. Checados antes de S1b/S2/S3/S8: só S1a sobrevive. */
const VETOS_BRANDOS: Veto[] = [
  veto('parcele', wb('\\bparcele\\b')),
  veto('novidades', wb('\\bnovidades?\\b')),
  veto('descubra', wb('\\bdescubra\\b')),
  veto('conheca', wb('\\bconhe[çc]a\\b')),
  veto('dica', wb('\\bdica\\b')),
  veto('saiba', wb('\\bsaiba\\b')),
  veto('entenda', wb('\\bentenda\\b')),
  veto('como-entender', wb('\\bcomo entender\\b')),
  veto('aproveite', wb('\\baproveite\\b')),
];
/** Brandos tardios: mais fracos ainda — só derrubam quando NENHUM sinal forte (S1a a S8) casou.
 *  "Taxa de adesão — boleto disponível" tem S2 e deve ficar forte; "Adesão à fatura digital",
 *  sem nenhum sinal forte, cai aqui e vira 'nao'. "com/de desconto" mora aqui (não em
 *  VETOS_BRANDOS) para não derrubar antes de S1b/S2/S3/S8: "Boleto disponível com desconto até
 *  dia 5" precisa chegar a S2. */
const VETOS_BRANDOS_TARDIOS: Veto[] = [
  veto('adesao', wb('\\bade(rir|r[êe]ncia|s[ãa]o)\\b')),
];
/** "com/de desconto" só é veto tardio se o assunto NÃO tiver nenhum verbo de ciclo de cobrança —
 *  reaproveita a flexão de vencimento de S2/S8. Com verbo de ciclo presente em qualquer posição do
 *  assunto (não só antes de "desconto"), o veto não se aplica e o assunto segue para os sinais
 *  fracos: "Fatura gerada com desconto por pagamento antecipado", "Mensalidade de outubro vence
 *  dia 5 com desconto", "Pague com desconto: fatura disponível" → não 'nao'. Sem nenhum verbo de
 *  ciclo, o veto ainda vale: "Parcele sua fatura com desconto", "Antecipe parcelas da sua fatura
 *  com desconto" → 'nao'. */
const CICLO_RE = wb(
  `\\b(fechou|fechada|chegou|dispon[ií]ve(?:l|is)|gerad[oa]s?|emitid[oa]s?|em atraso|pendente|em aberto|at[ée] (o )?dia \\d|${VENC_FLEXAO}|(?:ainda )?n[ãa]o (?:foi |est[áa] |estava )?paga)`,
);
const DESCONTO_TARDIO = veto(
  'com-desconto-sem-ciclo',
  wb('\\b(com|de) desconto\\b'),
);
const VETO_REMETENTE =
  /novidades\.|^novidades@|^news@|newsletter|^marketing@|(^|[@.\-_])promo([cç]([aã]o|[oõ]es)|cional|tions?)?(?=[@.\-_])|^ofertas?@|^comunicacao@/i;

// ---------- Sinais fortes ----------
const S1A = wb(
  '\\b(sua|a|nova)\\s+(fatura|cobran[çc]a|mensalidade|boleto|carnê)\\b.{0,45}\\b(fechou|fechada|chegou|dispon[ií]vel|gerada|emitida|vence|venceu|em atraso|pendente|em aberto|n[ãa]o\\s+(?:foi|est[áa]|estava)\\s+paga|ainda\\s+n[ãa]o\\s+paga)\\b(?!\\s+(?:juros|tarifas?|multas?|anuidade|taxas?|nada|mais))',
);
const MESES =
  'janeiro|fevereiro|mar[çc]o|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro';
/** "Extrato da fatura do Cartão Nubank": extrato DA FATURA é a fatura em si (o Nubank envia sob
 *  demanda, com CSV/PDF anexo). Exige a POSSE explícita ("extrato da/de/do(s) [sua] fatura") ou a
 *  forma invertida "fatura … extrato em anexo/disponível" — não uma janela cega de N caracteres:
 *  "Extrato de pontos Livelo para abater na fatura", "Extrato para IR e fatura de 2025" e "Extrato
 *  de rendimentos da fatura" têm as duas palavras perto e NÃO são cobrança. Avaliado depois dos
 *  vetos brandos (só S1a sobrevive a eles): "Saiba ler o extrato da sua fatura" é marketing. */
const S1C: RegExp[] = [
  wb(
    '\\bextratos?\\s+d(?:[aeo]s?|e|est[ae]s?|aquel[ae]s?)\\s+(?:(?:sua|seu|suas|seus|minha|minhas|nossa|nossas|nova|novas|[uú]ltimas?|est[ae]s?|aquelas?)\\s+)?faturas?\\b',
  ),
  wb(
    '\\bfaturas?\\b.{0,30}\\bextratos?\\b.{0,20}\\b(?:em\\s+anexo|anexad[oa]s?|dispon[ií]ve(?:l|is))\\b',
  ),
];
/** Temas em que "extrato da fatura" NÃO é cobrança: informe de rendimentos/IR, declaração,
 *  programa de pontos/milhas, investimentos, carteira. Derrubam S1c mesmo com a posse explícita —
 *  "Informe de rendimentos: extrato da fatura 2025", "Extrato da fatura de pontos Livelo". */
const S1C_TEMA_NAO_COBRANCA = wb(
  '\\b(informe de rendimentos?|imposto de renda|irpf|irrf|declara(?:[çc][ãa]o|r|ndo)|receita federal|le[ãa]o|rendimentos?|dividendos?|previd[êe]ncia|fundos?|pontos|milhas|fidelidade|recompensas?|clube de vantagens|livelo|esfera|smiles|latam pass|tudoazul|azul fidelidade|dotz|investimentos?|carteira)\\b',
);
/** A sigla "IR" só conta como tema fiscal com um companheiro fiscal por perto (ano, declaração,
 *  informe, imposto, Receita, anual); sem isso "Hora de IR ao app" ou um assunto em CAIXA ALTA
 *  ("... VAI IR POR E-MAIL") não podem derrubar uma cobrança. */
const IR_SIGLA_RE = wb('\\bIR\\b', 'u');
const IR_CONTEXTO_RE = wb(
  '\\b(20\\d\\d|declara[çc][ãa]o|informe|imposto|receita federal|anual|exerc[ií]cio)\\b',
);
const DOCUMENTO_COBRANCA_RE = wb(
  '\\bfaturas?\\b|\\bboletos?\\b|\\bcarnês?\\b|\\bcobran[çc]as?\\b|\\bmensalidades?\\b',
);
const S1B = wb(
  `\\bfatura\\s+(por e-?mail|digital|do m[êe]s|do cart[ãa]o)\\b.{0,20}[-–|:]\\s*(\\w+\\s*/\\s*\\d{4}|\\d{5,}|${MESES})`,
);
const S2: RegExp[] = [
  wb(
    `\\bboletos?\\b.{0,45}\\b(emitid|gerad|dispon[ií]vel|chegou|${VENC_FLEXAO})`,
  ),
  wb(`\\bcarnê\\b.{0,45}\\b(chegou|dispon[ií]vel|${VENC_FLEXAO})`),
];
const S3 =
  /^(fatura|faturas|fatura_digital|faturaporemail|boleto|boletos|invoice|invoices|\w*consorcio)($|[._-])/i;
const S8_VALOR = /R\$\s?(\d{1,3}(\.\d{3})*|\d+),\d{2}/;
const S8_VENC = wb(`\\b${VENC_FLEXAO}`);

// ---------- Sinais fracos ----------
export const SUBSTANTIVO_COBRANCA_RE = wb(
  '\\bfaturas?\\b|\\bboletos?\\b|\\bcarnês?\\b|\\bcobran[çc]a\\b|\\bcons[óo]rcio\\b|\\bfinanciamento\\b|\\bempr[ée]stimo\\b|\\bpresta[çc][ãa]o\\b|\\bvenc(e|imento)\\b|\\bmensalidade\\b|\\bparcelas?\\b|\\banuidade\\b|\\bconta de (luz|energia|[áa]gua|g[áa]s|internet|telefone)\\b|\\bseguro\\b|\\bsua conta\\b.{0,25}\\b(chegou|dispon[ií]vel|vence|venceu)\\b|\\bchegou sua conta\\b|linha digit[áa]vel|c[óo]digo de barras',
);
const S6_CASE_SENSITIVE = wb('\\b(IPTU|IPVA|DARF|DAS)\\b', 'u');
const S3F =
  /^(pagamento|pagamentos|financeiro|faturamento|cobranca|cobrancas|billing|cartao|cartoes)($|[._-])/i;
const S7 =
  /^(banco|bank|cartao|cartoes|fatura|cobranca|financeira|credito|consorcio|seguros?|energia|telecom)|(pay|bank|card)$/i;

export function triagem(
  remetente: string,
  assunto: string,
  opts: { marcado: boolean },
): ResultadoTriagem {
  const a = normalizar(assunto);
  const aLower = a.toLowerCase();
  const endereco = extrairEndereco(remetente);
  const local = endereco ? localPart(endereco) : '';
  const rotulos = endereco ? rotulosDominio(endereco) : [];
  const temSubstantivo =
    SUBSTANTIVO_COBRANCA_RE.test(aLower) || S6_CASE_SENSITIVE.test(a);
  const temaNaoCobranca =
    S1C_TEMA_NAO_COBRANCA.test(aLower) ||
    (IR_SIGLA_RE.test(a) && IR_CONTEXTO_RE.test(aLower));
  const base = {
    assuntoTemSubstantivoCobranca: temSubstantivo,
    // "Informe de rendimentos e sua fatura anual" nomeia "fatura", mas o tema é fiscal: não
    // vale como documento de cobrança (senão uma planilha anexa — E7 — fabricaria lançamento).
    assuntoTemDocumentoDeCobranca:
      DOCUMENTO_COBRANCA_RE.test(aLower) && !temaNaoCobranca,
    assuntoTemTemaNaoCobranca: temaNaoCobranca,
  };

  if (opts.marcado)
    return { ...base, nivel: 'forte', sinais: ['S4'], motivo: null };

  if (isSettledWithoutActiveBilling(a))
    return {
      ...base,
      nivel: 'nao',
      sinais: [],
      motivo: 'veto: pagamento já feito',
    };
  const extratoDaFatura = S1C.some((re) => re.test(aLower)) && !temaNaoCobranca;
  // O veto de "extrato" cede quando o assunto é o extrato DA FATURA (S1c) ou quando já carrega um
  // sinal forte próprio: "Sua fatura venceu — veja o extrato no app" é cobrança, não extrato.
  const sinalForteNoAssunto =
    S1A.test(aLower) ||
    S1B.test(aLower) ||
    S2.some((re) => re.test(aLower)) ||
    S3.test(local) ||
    (S8_VALOR.test(a) && S8_VENC.test(aLower));
  // "Lembrete: extrato e fatura de outubro", "Boleto e extrato de setembro": o assunto nomeia
  // um documento de cobrança — o veto de extrato não pode matar o e-mail antes de o corpo ser
  // lido; ele apenas deixa de ser forte e cai nos sinais fracos (E1–E7 decidem).
  // "Pagamento recebido! Nova fatura emitida": o veto de movimentação (recebido/estorno/agendado)
  // descreve a oração anterior; se outra oração traz cobrança vigente, ele não vale.
  const cobrancaVigente = hasActiveBillingClause(a);
  const duro = VETOS_DUROS.find(
    (v) =>
      v.re.test(aLower) &&
      !(
        v === VETO_EXTRATO &&
        (extratoDaFatura ||
          sinalForteNoAssunto ||
          base.assuntoTemDocumentoDeCobranca)
      ) &&
      !(VETOS_POR_ORACAO.has(v.rotulo) && cobrancaVigente),
  );
  if (duro)
    return {
      ...base,
      nivel: 'nao',
      sinais: [],
      motivo: `veto duro: ${duro.rotulo}`,
    };
  if (endereco && VETO_REMETENTE.test(endereco))
    return {
      ...base,
      nivel: 'nao',
      sinais: [],
      motivo: 'veto: remetente de marketing',
    };

  // S1a sobrevive a uma CAUDA de marketing ("Sua fatura chegou. Saiba como pagar"), não a uma
  // cabeça: "Entenda o que acontece quando a fatura fica em aberto" é conteúdo educativo.
  const s1a = S1A.exec(aLower);
  const brando = VETOS_BRANDOS.find((v) => v.re.test(aLower));
  const brandoAntesDoS1a =
    s1a !== null &&
    VETOS_BRANDOS.some((v) => {
      const b = v.re.exec(aLower);
      return b !== null && b.index < s1a.index;
    });
  if (s1a && !brandoAntesDoS1a)
    return { ...base, nivel: 'forte', sinais: ['S1a'], motivo: null };

  if (brando)
    return {
      ...base,
      nivel: 'nao',
      sinais: [],
      motivo: `veto brando: ${brando.rotulo}`,
    };

  if (S1B.test(aLower))
    return { ...base, nivel: 'forte', sinais: ['S1b'], motivo: null };
  if (extratoDaFatura)
    return { ...base, nivel: 'forte', sinais: ['S1c'], motivo: null };
  if (S2.some((re) => re.test(aLower)))
    return { ...base, nivel: 'forte', sinais: ['S2'], motivo: null };
  if (S3.test(local))
    return { ...base, nivel: 'forte', sinais: ['S3'], motivo: null };
  if (S8_VALOR.test(a) && S8_VENC.test(aLower))
    return { ...base, nivel: 'forte', sinais: ['S8'], motivo: null };

  const brandoTardio = VETOS_BRANDOS_TARDIOS.find((v) => v.re.test(aLower));
  if (brandoTardio)
    return {
      ...base,
      nivel: 'nao',
      sinais: [],
      motivo: `veto brando: ${brandoTardio.rotulo}`,
    };
  if (DESCONTO_TARDIO.re.test(aLower) && !CICLO_RE.test(aLower)) {
    return {
      ...base,
      nivel: 'nao',
      sinais: [],
      motivo: `veto brando: ${DESCONTO_TARDIO.rotulo}`,
    };
  }

  const fracos: string[] = [];
  if (temSubstantivo) fracos.push('S6');
  if (S3F.test(local)) fracos.push('S3f');
  if (rotulos.some((r) => S7.test(r))) fracos.push('S7');
  if (fracos.length > 0)
    return { ...base, nivel: 'fraco', sinais: fracos, motivo: null };

  return { ...base, nivel: 'nao', sinais: [], motivo: 'sem sinal' };
}
