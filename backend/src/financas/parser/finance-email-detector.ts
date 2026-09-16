import { extrairEndereco, localPart, rotulosDominio } from '../../common/email-address.util';
import { normalizar, wb } from '../../common/text-match.util';
import { isSettledPaymentSubject } from './invoice-subject-patterns';

export type NivelTriagem = 'nao' | 'forte' | 'fraco';
export interface ResultadoTriagem {
  nivel: NivelTriagem;
  sinais: string[];
  motivo: string | null;
  assuntoTemSubstantivoCobranca: boolean;
}

// ---------- Vetos ----------
/** Duros: nunca criam lançamento, nem com S1a. Marketing, segurança, pagamento já feito, movimentações
 *  que NÃO são cobrança (pix/depósito/estorno recebido, agendado). */
const VETOS_DUROS: RegExp[] = [
  wb('\\bextratos?\\b'),
  wb('d[eé]bito autom[aá]tico .{0,30}(conclu[ií]d|cadastrad|ativad)'),
  wb('recibo de pedido'),
  wb('pedido .{0,20}(faturado|enviado|entregue)'),
  wb('\\bseu pedido\\b'),
  wb('\\bpesquisa\\b'),
  wb('\\bconvite\\b'),
  wb('\\bganhe\\b'),
  wb('\\bsorteio\\b'),
  wb('\\bcashback\\b'),
  wb('\\d+ ?% ?(off|de desconto)'),
  wb('\\bsem juros\\b'),
  wb('\\bsimule\\b'),
  wb('pr[ée]-aprovad'),
  wb('\\bcontestad'),
  wb('contesta[çc][ãa]o'),
  wb('em an[áa]lise'),
  wb('\\bdisputa\\b'),
  wb('\\bcomo (funciona|aderir|receber)\\b'),
  wb('cadastre-se'),
  wb('\\bprefira\\b'),
  wb('\\bagora voc[êe] pode\\b'),
  wb('\\bsenha\\b'),
  wb('\\bc[óo]digo de (verifica[çc][ãa]o|seguran[çc]a|acesso)\\b'),
  wb('\\balerta de seguran[çc]a\\b'),
  wb('\\brenove\\b'),
  wb('\\bcupom\\b'),
  wb('\\bofertas?\\b'),
  wb('promo[çc][ãa]o'),
  wb('\\bagendad[oa]\\b'),
  wb('\\bestorno\\b'),
  wb('\\brecebid[oa]\\b'),
  wb('\\b(receipt|paid|payment (received|successful|confirmed))\\b'),
];
/** Brandos: cauda de marketing num aviso legítimo ("Sua fatura chegou. Saiba como pagar") não o anula —
 *  só derrubam quando S1a NÃO casa. Checados antes de S1b/S2/S3/S8: só S1a sobrevive. */
const VETOS_BRANDOS: RegExp[] = [
  wb('\\bnovidades?\\b'), wb('\\bdescubra\\b'), wb('\\bconhe[çc]a\\b'), wb('\\bdica\\b'),
  wb('\\bsaiba\\b'), wb('\\bentenda\\b'), wb('\\bcomo entender\\b'), wb('\\baproveite\\b'),
  wb('\\b(com|de) desconto\\b'),
];
/** Brandos tardios: mais fracos ainda — só derrubam quando NENHUM sinal forte (S1a a S8) casou.
 *  "Taxa de adesão — boleto disponível" tem S2 e deve ficar forte; "Adesão à fatura digital",
 *  sem nenhum sinal forte, cai aqui e vira 'nao'. */
const VETOS_BRANDOS_TARDIOS: RegExp[] = [
  wb('\\bade(rir|r[êe]ncia|s[ãa]o)\\b'),
];
const VETO_REMETENTE =
  /novidades\.|^novidades@|^news@|newsletter|^marketing@|(^|[.\-_])promo(?=[@.\-_])|promo[cç][aã]o@|^ofertas?@|^comunicacao@/i;

// ---------- Sinais fortes ----------
const S1A = wb(
  '\\b(sua|a|nova)\\s+(fatura|cobran[çc]a|mensalidade|boleto|carnê)\\b.{0,45}\\b(fechou|fechada|chegou|dispon[ií]vel|gerada|emitida|vence|venceu|em atraso|pendente)\\b',
);
const MESES = 'janeiro|fevereiro|mar[çc]o|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro';
const S1B = wb(`\\bfatura\\s+(por e-?mail|digital|do m[êe]s|do cart[ãa]o)\\b.{0,20}[-–|:]\\s*(\\w+\\s*/\\s*\\d{4}|\\d{5,}|${MESES})`);
const VENC_FLEXAO = 'venc(?:e|eu|ido|ida|imento|imentos)\\b';
const S2: RegExp[] = [
  wb(`\\bboletos?\\b.{0,45}\\b(emitid|gerad|dispon[ií]vel|chegou|${VENC_FLEXAO})`),
  wb(`\\bcarnê\\b.{0,45}\\b(chegou|dispon[ií]vel|${VENC_FLEXAO})`),
];
const S3 = /^(fatura|faturas|fatura_digital|faturaporemail|boleto|boletos|invoice|invoices|\w*consorcio)($|[._-])/i;
const S8_VALOR = /R\$\s?(\d{1,3}(\.\d{3})*|\d+),\d{2}/;
const S8_VENC = wb(`\\b${VENC_FLEXAO}`);

// ---------- Sinais fracos ----------
export const SUBSTANTIVO_COBRANCA_RE = wb(
  '\\bfaturas?\\b|\\bboletos?\\b|\\bcarnês?\\b|\\bcobran[çc]a\\b|\\bcons[óo]rcio\\b|\\bfinanciamento\\b|\\bempr[ée]stimo\\b|\\bpresta[çc][ãa]o\\b|\\bvenc(e|imento)\\b|\\bmensalidade\\b|\\bparcelas?\\b|\\banuidade\\b|\\bconta de (luz|energia|[áa]gua|g[áa]s|internet|telefone)\\b|\\bseguro\\b|\\bsua conta\\b.{0,25}\\b(chegou|dispon[ií]vel|vence|venceu)\\b|\\bchegou sua conta\\b|linha digit[áa]vel|c[óo]digo de barras',
);
const S6_CASE_SENSITIVE = wb('\\b(IPTU|IPVA|DARF|DAS)\\b', 'u');
const S3F = /^(pagamento|pagamentos|financeiro|faturamento|cobranca|cobrancas|billing|cartao|cartoes)($|[._-])/i;
const S7 = /^(banco|bank|cartao|cartoes|fatura|cobranca|financeira|credito|consorcio|seguros?|energia|telecom)|(pay|bank|card)$/i;

export function triagem(remetente: string, assunto: string, opts: { marcado: boolean }): ResultadoTriagem {
  const a = normalizar(assunto);
  const aLower = a.toLowerCase();
  const endereco = extrairEndereco(remetente);
  const local = endereco ? localPart(endereco) : '';
  const rotulos = endereco ? rotulosDominio(endereco) : [];
  const temSubstantivo = SUBSTANTIVO_COBRANCA_RE.test(aLower) || S6_CASE_SENSITIVE.test(a);
  const base = { assuntoTemSubstantivoCobranca: temSubstantivo };

  if (opts.marcado) return { ...base, nivel: 'forte', sinais: ['S4'], motivo: null };

  if (isSettledPaymentSubject(a)) return { ...base, nivel: 'nao', sinais: [], motivo: 'veto: pagamento já feito' };
  const duro = VETOS_DUROS.find((re) => re.test(aLower));
  if (duro) return { ...base, nivel: 'nao', sinais: [], motivo: `veto duro: ${duro.source}` };
  if (endereco && VETO_REMETENTE.test(endereco)) return { ...base, nivel: 'nao', sinais: [], motivo: 'veto: remetente de marketing' };

  if (S1A.test(aLower)) return { ...base, nivel: 'forte', sinais: ['S1a'], motivo: null };

  const brando = VETOS_BRANDOS.find((re) => re.test(aLower));
  if (brando) return { ...base, nivel: 'nao', sinais: [], motivo: `veto brando: ${brando.source}` };

  if (S1B.test(aLower)) return { ...base, nivel: 'forte', sinais: ['S1b'], motivo: null };
  if (S2.some((re) => re.test(aLower))) return { ...base, nivel: 'forte', sinais: ['S2'], motivo: null };
  if (S3.test(local)) return { ...base, nivel: 'forte', sinais: ['S3'], motivo: null };
  if (S8_VALOR.test(a) && S8_VENC.test(aLower)) return { ...base, nivel: 'forte', sinais: ['S8'], motivo: null };

  const brandoTardio = VETOS_BRANDOS_TARDIOS.find((re) => re.test(aLower));
  if (brandoTardio) return { ...base, nivel: 'nao', sinais: [], motivo: `veto brando: ${brandoTardio.source}` };

  const fracos: string[] = [];
  if (temSubstantivo) fracos.push('S6');
  if (S3F.test(local)) fracos.push('S3f');
  if (rotulos.some((r) => S7.test(r))) fracos.push('S7');
  if (fracos.length > 0) return { ...base, nivel: 'fraco', sinais: fracos, motivo: null };

  return { ...base, nivel: 'nao', sinais: [], motivo: 'sem sinal' };
}
