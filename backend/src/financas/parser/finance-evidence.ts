import { normalizar, wb } from '../../common/text-match.util';
import { extrairCodigoBarras, extrairDataVencimento, extrairValor } from './finance-extractors';
import { isSettledPaymentSubject } from './invoice-subject-patterns';

export interface AnexoMeta { filename: string; mimeType: string; size: number; attachmentId: string }
export type Evidencia = 'E1' | 'E2' | 'E3' | 'E4' | 'E5' | 'E6';
export const CABECA_EVIDENCIA = 1500;

const PIX_RE = wb('\\bpix copia e cola\\b|\\bchave pix\\b');
const MOEDA_RE = /R\$\s?(\d{1,3}(\.\d{3})*|\d+),\d{2}/;
const E5_RE = wb('\\bsua (fatura|conta)\\b.{0,30}\\b(est[áa]|segue) (anexa|anexada|em anexo)\\b');
const E6_RE = /fatura|invoice|boleto|cobranca/i;

export function evidenciasDeCobranca(texto: string, anexos: AnexoMeta[], recebidoEm: Date): Set<Evidencia> {
  const cabeca = normalizar(texto).slice(0, CABECA_EVIDENCIA);
  const ev = new Set<Evidencia>();
  const valor = extrairValor(cabeca);
  if (valor.valor !== null && valor.anchored && valor.ancoraCobranca) ev.add('E1');
  const data = extrairDataVencimento(cabeca, recebidoEm);
  if (data.data !== null && data.anchored) ev.add('E2');
  if (extrairCodigoBarras(cabeca) !== null) ev.add('E3');
  const linhas = cabeca.split(/\r?\n/);
  for (let i = 0; i < linhas.length; i++) {
    if (PIX_RE.test(linhas[i]) && (MOEDA_RE.test(linhas[i]) || MOEDA_RE.test(linhas[i + 1] ?? ''))) { ev.add('E4'); break; }
  }
  if (E5_RE.test(cabeca)) ev.add('E5');
  if (anexos.some((a) => E6_RE.test(a.filename))) ev.add('E6');
  return ev;
}

export function evidenciaSuficiente(ev: Set<Evidencia>, assuntoTemSubstantivoCobranca: boolean): boolean {
  if (['E1', 'E3', 'E4', 'E5', 'E6'].some((e) => ev.has(e as Evidencia))) return true;
  return ev.has('E2') && assuntoTemSubstantivoCobranca;
}

const NEGATIVAS: RegExp[] = [
  wb('\\b(pesquisa de satisfa[çc][ãa]o|avalie (seu|nosso|o) atendimento)\\b'),
  wb('\\brecebeu (um|uma) (pix|transfer[êe]ncia|dep[óo]sito)\\b'),
  wb('\\b(pix|transfer[êe]ncia|dep[óo]sito|compra|rendimento|pagamento|estorno) .{0,25}(recebid|aprovad|realizad|agendad|efetuad|conclu[ií]d)'),
  wb('\\bestorno\\b'),
];

/** Nas 3 primeiras linhas não vazias do texto OU no assunto. Exceto com marcador (decidido pelo chamador). */
export function temEvidenciaNegativa(texto: string, assunto: string): boolean {
  const cabeca = normalizar(texto).split(/\r?\n/).map((l) => l.trim()).filter(Boolean).slice(0, 3).join('\n');
  const alvo = `${normalizar(assunto)}\n${cabeca}`;
  if (cabeca.split('\n').some((l) => isSettledPaymentSubject(l))) return true;
  return NEGATIVAS.some((re) => re.test(alvo));
}
