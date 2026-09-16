import { wb } from '../../common/text-match.util';

// ---------- Valor ----------
/** Âncoras de COBRANÇA: provam que o número é um valor devido (evidência E1). */
export const ANCORAS_VALOR_COBRANCA: RegExp[] = [
  wb('\\bvalor a pagar\\b'), wb('\\btotal a pagar\\b'), wb('\\btotal da fatura\\b'), wb('\\bvalor da fatura\\b'),
  wb('\\bvalor do boleto\\b'), wb('\\bvalor da conta\\b'), wb('\\btotal da conta\\b'),
];
/** Âncoras só de EXTRAÇÃO: localizam o número, mas não provam cobrança ("Pix … no valor de"). */
export const ANCORAS_VALOR_EXTRACAO: RegExp[] = [
  wb('\\bvalor total\\b'), wb('\\bno valor de\\b'), wb('\\bvalor:'), wb('\\btotal:'),
];
const TODAS_ANCORAS_VALOR = [...ANCORAS_VALOR_COBRANCA, ...ANCORAS_VALOR_EXTRACAO];

const MOEDA_NUM = String.raw`((?:\d{1,3}(?:\.\d{3})*|\d+),\d{2})`;
/** Com prefixo R$ obrigatório (fallback não ancorado). */
const MOEDA_RS_G = new RegExp(String.raw`R\$\s*${MOEDA_NUM}`, 'g');
/** Prefixo R$ opcional — SÓ para texto ancorado. Exige que não venha colado a dígito/%. */
const MOEDA_OPCIONAL_RE = new RegExp(String.raw`(?:R\$\s*)?(?<![\d,.])${MOEDA_NUM}(?![\d%])`);
const PARCELAMENTO_RE = /\d+\s*(x|vezes)\s+de|parcelas?\s+de|m[ií]nimo/i;
/** "após/mínimo" em qualquer lugar dos primeiros 15 caracteres depois da âncora, mas só no trecho
 *  ANTES da primeira moeda — texto depois da moeda (ex.: "(após o vencimento)" numa frase seguinte)
 *  não deve rejeitar um valor já reconhecido (rótulos como "Valor a pagar:" continuam rejeitados). */
const APOS_MINIMO_INICIO_RE = wb(String.raw`^.{0,15}?\b(ap[óo]s|m[ií]nimo)\b`);

function parseBr(raw: string): number {
  return parseFloat(raw.replace(/\./g, '').replace(',', '.'));
}
function zeroParaNull(v: number): number | null {
  return v > 0 ? v : null;
}

export function extrairValor(texto: string): { valor: number | null; anchored: boolean; ancoraCobranca: boolean } {
  const linhas = texto.split(/\r?\n/);
  for (const ancora of TODAS_ANCORAS_VALOR) {
    const ehCobranca = ANCORAS_VALOR_COBRANCA.includes(ancora);
    const global = new RegExp(ancora.source, ancora.flags.includes('g') ? ancora.flags : `${ancora.flags}g`);
    for (let i = 0; i < linhas.length; i++) {
      const linha = linhas[i];
      const matches = [...linha.matchAll(global)];
      if (matches.length === 0) continue;
      for (const m of matches) {
        const depois = linha.slice((m.index ?? 0) + m[0].length);
        // Segmento até a primeira moeda: se houver parcelamento ou "após/mínimo" antes dela, o
        // número é parcela/valor mínimo — mas isso só vale para o texto ANTES da moeda.
        const primeiraMoeda = depois.match(MOEDA_OPCIONAL_RE);
        if (!primeiraMoeda || primeiraMoeda.index === undefined) continue;
        const antesMoeda = depois.slice(0, primeiraMoeda.index);
        if (APOS_MINIMO_INICIO_RE.test(antesMoeda)) continue;
        if (PARCELAMENTO_RE.test(depois.slice(0, primeiraMoeda.index + primeiraMoeda[0].length))) continue;
        return { valor: zeroParaNull(parseBr(primeiraMoeda[1])), anchored: true, ancoraCobranca: ehCobranca };
      }
      // Rótulo numa linha, valor na seguinte (HTML <div>label</div><div>valor</div>).
      const proxima = linhas[i + 1];
      if (proxima !== undefined && proxima.trim() !== '' && !PARCELAMENTO_RE.test(proxima)
        && !TODAS_ANCORAS_VALOR.some((a) => a.test(proxima))) {
        const m2 = proxima.match(MOEDA_OPCIONAL_RE);
        if (m2) return { valor: zeroParaNull(parseBr(m2[1])), anchored: true, ancoraCobranca: ehCobranca };
      }
    }
  }
  const todas = [...texto.matchAll(MOEDA_RS_G)];
  if (todas.length === 1) {
    // Mesmo sem âncora, não aceita um valor cuja própria linha denuncie parcela/mínimo
    // (ex.: "12x de R$ 100,00", "Valor mínimo R$ 50,00").
    const idx = todas[0].index ?? 0;
    const inicioLinha = texto.lastIndexOf('\n', idx - 1) + 1;
    const fimLinhaBusca = texto.indexOf('\n', idx);
    const fimLinha = fimLinhaBusca === -1 ? texto.length : fimLinhaBusca;
    const linhaDoMatch = texto.slice(inicioLinha, fimLinha);
    if (!PARCELAMENTO_RE.test(linhaDoMatch)) {
      return { valor: zeroParaNull(parseBr(todas[0][1])), anchored: false, ancoraCobranca: false };
    }
  }
  return { valor: null, anchored: false, ancoraCobranca: false };
}

// ---------- Data ----------
/** Lista única, usada pela extração e pela evidência E2. A forma "vence em/no dia/dia" vira conector
 *  lido logo após a âncora. */
export const DATE_ANCHORS: RegExp[] = [
  wb('\\bdata de vencimento\\b'), wb('\\bvencimento\\b'), wb('\\bvence\\b'), wb('\\bpague at[ée]\\b'), wb('\\bpagar at[ée]\\b'),
];
/** Conector entre a âncora e a data: pontuação ("."/":"/"-") E/OU palavra ("dia"/"no dia"/"em"/
 *  "para o dia") podem aparecer juntos ("Vencimento: dia 10", "Vencimento - dia 10"). */
const CONECTOR_RE = /^\s*(?:[:.\-–—]+\s*)?(?:(?:em|no dia|dia|para o dia)\s+)?\s*/i;
const MESES = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];
/** dd/mm/aaaa, dd.mm.aaaa ou dd-mm-aaaa — o separador precisa ser o mesmo nas duas posições.
 *  Guardas de dígito (lookbehind/lookahead) evitam casar um trecho no MEIO de uma data ISO
 *  (aaaa-mm-dd), ex.: "2026-10-10" não deve virar "26-10-20" nem "10-10-20" por acidente. */
const DATA_COMPLETA_RE = /(?<!\d)(\d{1,2})([./-])(\d{1,2})\2(\d{4}|\d{2})(?!\d)/;
const DATA_ISO_RE = /(\d{4})-(\d{2})-(\d{2})/;
const DATA_EXTENSO_RE = new RegExp(String.raw`(\d{1,2})\s+de\s+(${MESES.join('|')})(?:\s+de\s+(\d{4}))?`, 'i');
const DATA_DDMM_RE = /(\d{1,2})\/(\d{1,2})(?![/\d])/;
/** Só-dia ("vence dia 10"): rejeita quando o número é seguido de "dias" ("em 3 dias" não é data),
 *  continua como data com outro separador ("05.10" — isso é dd.mm, não o dia 5), ou é seguido de
 *  uma barra solta mesmo com espaço ou texto não numérico ("10/out", "10 / 10 / 2026"). */
const SO_DIA_RE = /^(\d{1,2})\b(?!\s*(?:\/|[.-]\s*\d|dias?\b|de\s))/;

function dataValida(y: number, m: number, d: number): Date | null {
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  const dt = new Date(Date.UTC(y, m - 1, d));
  return dt.getUTCMonth() === m - 1 && dt.getUTCDate() === d ? dt : null;
}

export function inferirAno(dia: number, mes: number, recebidoEm: Date): Date | null {
  const base = recebidoEm.getUTCFullYear();
  const candidatos = [base - 1, base, base + 1]
    .map((y) => dataValida(y, mes, dia))
    .filter((d): d is Date => d !== null);
  if (candidatos.length === 0) return null;
  return candidatos.reduce((melhor, d) =>
    Math.abs(d.getTime() - recebidoEm.getTime()) < Math.abs(melhor.getTime() - recebidoEm.getTime()) ? d : melhor);
}

export function proximoDia(dia: number, recebidoEm: Date): Date | null {
  if (dia < 1 || dia > 31) return null;
  const y = recebidoEm.getUTCFullYear(), m = recebidoEm.getUTCMonth() + 1;
  for (const [yy, mm] of [[y, m], m === 12 ? [y + 1, 1] : [y, m + 1]]) {
    const d = dataValida(yy, mm, dia);
    if (d && d.getTime() >= Date.UTC(y, m - 1, recebidoEm.getUTCDate())) {
      const dias = (d.getTime() - recebidoEm.getTime()) / 86_400_000;
      return dias <= 45 ? d : null;
    }
  }
  return null;
}

/** Formatos COMPLETOS (com ano) — permitidos em qualquer lugar. ISO (aaaa-mm-dd) é avaliado
 *  ANTES de dd/mm/aaaa: sem essa ordem, DATA_COMPLETA_RE pode casar um trecho no meio de uma
 *  data ISO (ex.: "2026-10-10" lido como dia 10, mês 10, ano 20 → 2010-10-26, errado). */
function dataCompleta(texto: string): Date | null {
  const iso = texto.match(DATA_ISO_RE);
  if (iso) return dataValida(Number(iso[1]), Number(iso[2]), Number(iso[3]));
  const n = texto.match(DATA_COMPLETA_RE);
  if (n) { const yyyy = n[4].length === 2 ? 2000 + Number(n[4]) : Number(n[4]); return dataValida(yyyy, Number(n[3]), Number(n[1])); }
  const ext = texto.match(DATA_EXTENSO_RE);
  if (ext && ext[3]) return dataValida(Number(ext[3]), MESES.indexOf(ext[2].toLowerCase()) + 1, Number(ext[1]));
  return null;
}
/** Formatos SEM ano — só depois de uma âncora. Ordem: completo > dd/mm > "dd de mês" > só dia. */
function dataAposAncora(depois: string, recebidoEm: Date): Date | null {
  const semConector = depois.replace(CONECTOR_RE, '');
  const completa = dataCompleta(semConector);
  if (completa) return completa;
  const ddmm = semConector.match(DATA_DDMM_RE);
  if (ddmm && semConector.indexOf(ddmm[0]) < 40) return inferirAno(Number(ddmm[1]), Number(ddmm[2]), recebidoEm);
  const ext = semConector.match(DATA_EXTENSO_RE);
  if (ext) return inferirAno(Number(ext[1]), MESES.indexOf(ext[2].toLowerCase()) + 1, recebidoEm);
  const soDia = semConector.match(SO_DIA_RE);
  if (soDia) return proximoDia(Number(soDia[1]), recebidoEm);
  return null;
}

export function extrairDataVencimento(texto: string, recebidoEm: Date): { data: Date | null; anchored: boolean } {
  const linhas = texto.split(/\r?\n/);
  for (const ancora of DATE_ANCHORS) {
    for (let i = 0; i < linhas.length; i++) {
      const m = linhas[i].match(ancora);
      if (!m || m.index === undefined) continue;
      const depois = linhas[i].slice(m.index + m[0].length);
      const d = dataAposAncora(depois, recebidoEm);
      if (d) return { data: d, anchored: true };
      const proxima = linhas[i + 1];
      if (proxima !== undefined && depois.replace(CONECTOR_RE, '').trim() === '') {
        const d2 = dataAposAncora(proxima, recebidoEm);
        if (d2) return { data: d2, anchored: true };
      }
    }
  }
  const fallback = dataCompleta(texto);
  return fallback ? { data: fallback, anchored: false } : { data: null, anchored: false };
}

// ---------- Código de barras ----------
const BOLETO_47_RE = /^\d{5}\.\d{5}\s\d{5}\.\d{6}\s\d{5}\.\d{6}\s\d\s\d{14}$/m;
const CONCESSIONARIA_48_RE = /^\d{11}-\d\s\d{11}-\d\s\d{11}-\d\s\d{11}-\d$/m;
export function extrairCodigoBarras(texto: string): string | null {
  return texto.match(BOLETO_47_RE)?.[0] ?? texto.match(CONCESSIONARIA_48_RE)?.[0] ?? null;
}
