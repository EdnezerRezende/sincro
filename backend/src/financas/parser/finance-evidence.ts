import { normalizar, wb } from '../../common/text-match.util';
import {
  extrairCodigoBarras,
  extrairDataVencimento,
  extrairValor,
} from './finance-extractors';
import { isSettledWithoutActiveBilling } from './invoice-subject-patterns';

export interface AnexoMeta {
  filename: string;
  mimeType: string;
  size: number;
  attachmentId: string;
}
export type Evidencia = 'E1' | 'E2' | 'E3' | 'E4' | 'E5' | 'E6' | 'E7';
export const CABECA_EVIDENCIA = 1500;

const PIX_RE = wb('\\bpix copia e cola\\b|\\bchave pix\\b');
const MOEDA_RE = /R\$\s?(\d{1,3}(\.\d{3})*|\d+),\d{2}/;
const E5_RE = wb(
  '\\bsua (fatura|conta)\\b.{0,30}\\b(est[áa]|segue) (anexa|anexada|em anexo)\\b',
);
const E6_RE = /fatura|invoice|boleto|cobran[çc]a/i;
const E7_RE = /\.(csv|xlsx?)$/i;

export function evidenciasDeCobranca(
  texto: string,
  anexos: AnexoMeta[],
  recebidoEm: Date,
): Set<Evidencia> {
  const cabeca = normalizar(texto).slice(0, CABECA_EVIDENCIA);
  const ev = new Set<Evidencia>();
  const valor = extrairValor(cabeca);
  if (valor.valor !== null && valor.anchored && valor.ancoraCobranca)
    ev.add('E1');
  const data = extrairDataVencimento(cabeca, recebidoEm);
  if (data.data !== null && data.anchored) ev.add('E2');
  if (extrairCodigoBarras(cabeca) !== null) ev.add('E3');
  const linhas = cabeca.split(/\r?\n/);
  for (let i = 0; i < linhas.length; i++) {
    if (
      PIX_RE.test(linhas[i]) &&
      (MOEDA_RE.test(linhas[i]) || MOEDA_RE.test(linhas[i + 1] ?? ''))
    ) {
      ev.add('E4');
      break;
    }
  }
  if (E5_RE.test(cabeca)) ev.add('E5');
  // E6 só para anexo que não é planilha: "fatura-2025.csv" é planilha (E7, que exige documento de
  // cobrança no assunto) — senão o NOME do anexo furaria a trava fiscal ("Informe de rendimentos e
  // sua fatura anual" + fatura-2025.csv geraria lançamento).
  if (
    anexos.some((a) => {
      const nome = a.filename.normalize('NFC').trim();
      return E6_RE.test(nome) && !E7_RE.test(nome);
    })
  )
    ev.add('E6');
  // E7: anexo tabular (CSV/XLS/XLSX) — é como bancos mandam extrato de fatura/lançamentos (o
  // Nubank anexa o CSV da fatura pedida no app). Só a extensão conta, não o nome. XML fica de
  // fora: em e-mail brasileiro é NF-e, convite de agenda ou assinatura. Planilha também chega em
  // relatório de investimentos, por isso E7 nunca basta sozinha (ver `evidenciaSuficiente`).
  if (anexos.some((a) => E7_RE.test(a.filename.normalize('NFC').trim())))
    ev.add('E7');
  return ev;
}

export function evidenciaSuficiente(
  ev: Set<Evidencia>,
  assuntoTemSubstantivoCobranca: boolean,
  assuntoTemDocumentoDeCobranca = false,
  assuntoTemTemaNaoCobranca = false,
): boolean {
  // Tema fiscal/fidelidade/investimento no assunto ("Informe de rendimentos e sua fatura anual"):
  // o NOME de um anexo (E6 pdf, E7 planilha) ou uma data (E2) nunca bastam — só cobrança explícita
  // no corpo (valor ancorado, código de barras, pix).
  if (assuntoTemTemaNaoCobranca)
    return ['E1', 'E3', 'E4'].some((e) => ev.has(e as Evidencia));
  if (['E1', 'E3', 'E4', 'E5', 'E6'].some((e) => ev.has(e as Evidencia)))
    return true;
  // E2 (só data) é ambígua sozinha: precisa do assunto falar em cobrança (fatura, consórcio,
  // seguro, parcela...). E7 (só planilha anexa) é mais fraca ainda — "Relatório anual do seu
  // consórcio" com cotas.xlsx não é cobrança — e exige que o assunto nomeie o DOCUMENTO
  // (fatura/boleto/carnê/cobrança/mensalidade).
  if (ev.has('E2') && assuntoTemSubstantivoCobranca) return true;
  return ev.has('E7') && assuntoTemDocumentoDeCobranca;
}

const NEGATIVAS: RegExp[] = [
  wb('\\b(pesquisa de satisfa[çc][ãa]o|avalie (seu|nosso|o) atendimento)\\b'),
  wb('\\brecebeu (um|uma) (pix|transfer[êe]ncia|dep[óo]sito)\\b'),
  wb(
    '\\b(pix|transfer[êe]ncia|dep[óo]sito|compra|rendimento|pagamento|estorno) .{0,25}(recebid|aprovad|realizad|agendad|efetuad|conclu[ií]d)',
  ),
  wb('\\bestorno\\b'),
];

/** Nas 3 primeiras linhas não vazias do texto OU no assunto. Exceto com marcador (decidido pelo chamador). */
export function temEvidenciaNegativa(texto: string, assunto: string): boolean {
  const assuntoNormalizado = normalizar(assunto);
  const cabeca = normalizar(texto)
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter(Boolean)
    .slice(0, 3)
    .join('\n');
  const alvo = `${assuntoNormalizado}\n${cabeca}`;
  // Por oração, como na triagem: "Fatura anterior paga. Fatura de outubro disponível" não é negativa.
  if (isSettledWithoutActiveBilling(assuntoNormalizado)) return true;
  // Também por oração no corpo: "Recebemos o pagamento da fatura anterior. A fatura de outubro já
  // está disponível." não é negativa.
  if (cabeca.split('\n').some((l) => isSettledWithoutActiveBilling(l)))
    return true;
  return NEGATIVAS.some((re) => re.test(alvo));
}
