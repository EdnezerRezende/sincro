import { Injectable } from '@nestjs/common';
import { normalizar, wb } from '../../common/text-match.util';
import { ResultadoTriagem } from './finance-email-detector';
import {
  AnexoMeta,
  evidenciaSuficiente,
  evidenciasDeCobranca,
  temEvidenciaNegativa,
} from './finance-evidence';
import {
  extrairCodigoBarras,
  extrairDataVencimento,
  extrairValor,
} from './finance-extractors';
import { resolverInstituicao } from './institution-map';
import { isCardInvoiceSubject } from './invoice-subject-patterns';

/** Sobe a cada mudança de regra; `EmailSummary.parserFinancasVersao < FINANCE_PARSER_VERSION` é reprocessado. */
export const FINANCE_PARSER_VERSION = 2;
export const CABECA_TIPO = 600;

export type TipoLancamentoParser = 'DESPESA' | 'FATURA_CARTAO';
export interface ParsedLancamento {
  tipo: TipoLancamentoParser;
  descricao: string;
  instituicao: string;
  valor: number | null;
  dataVencimento: Date;
  dataEncontrada: boolean;
  codigoBarras: string | null;
}
export interface ParseParams {
  remetente: string;
  assunto: string;
  corpo: string;
  recebidoEm: Date;
  triagem: ResultadoTriagem;
  anexos: AnexoMeta[];
}

const CARTAO_PERTO_DE_FATURA_RE = wb(
  '\\bcart(ão|ao|[õo]es)\\b.{0,40}\\bfatura\\b|\\bfatura\\b.{0,40}\\bcart(ão|ao|[õo]es)\\b',
);
const BANDEIRA_PERTO_DE_FATURA_RE = wb(
  '\\b(visa|mastercard|master|amex|hipercard)\\b.{0,40}\\bfatura\\b|\\bfatura\\b.{0,40}\\b(visa|mastercard|master|amex|hipercard)\\b',
);
/** Emissor MAPEADO como cartão (`tipoPadrao === 'CARTAO'`, ex.: Pefisa) já é confiável o bastante
 *  para não exigir palavra de ciclo de vida — basta "fatura(s)"
 *  no ASSUNTO. Ex.: Pefisa "Sua Fatura CELEBRE! ELO MAIS" com corpo de cobrança em atraso ("Ainda
 *  não identificamos o pagamento de sua fatura...") não tem "fechou"/"disponível"/etc., mas é
 *  inequivocamente uma fatura de cartão pelo remetente mapeado + assunto. Deliberadamente restrita
 *  ao assunto (não ao corpo): um emissor mapeado que manda cobrança de outra coisa citando
 *  "fatura" de passagem no corpo não deve virar FATURA_CARTAO por isso. */
const ASSUNTO_TEM_FATURA_RE = wb('\\bfaturas?\\b');
/** Um emissor de cartão também cobra outros produtos: "Fatura do seu consórcio", "Fatura do
 *  empréstimo" etc. não são fatura de cartão — o atalho abaixo não se aplica a elas. */
const PRODUTO_NAO_CARTAO_RE = wb(
  '\\b(cons[óo]rcio|empr[ée]stimo|financiamento|seguro|presta[çc][ãa]o|consignad[oa])\\b',
);

/** Orientado à `triagem()` de `finance-email-detector.ts`: `forte` sempre gera lançamento (salvo
 *  evidência negativa no corpo); `fraco` só gera com evidência de cobrança suficiente (E1–E6). O
 *  `INSTITUTION_MAP` (via `resolverInstituicao`) é só enriquecimento — nome/tipoPadrão — nunca a
 *  porta de entrada da detecção. */
@Injectable()
export class EmailFinanceRegexParserService {
  parse(p: ParseParams): ParsedLancamento | null {
    if (p.triagem.nivel === 'nao') return null;
    const marcado = p.triagem.sinais.includes('S4');
    const corpo = normalizar(p.corpo);
    if (!marcado && temEvidenciaNegativa(corpo, p.assunto)) return null;
    if (p.triagem.nivel === 'fraco') {
      const ev = evidenciasDeCobranca(corpo, p.anexos, p.recebidoEm);
      if (!evidenciaSuficiente(ev, p.triagem.assuntoTemSubstantivoCobranca))
        return null;
    }

    const inst = resolverInstituicao(p.remetente, p.assunto);
    const { valor } = extrairValor(corpo);
    const data = extrairDataVencimento(corpo, p.recebidoEm);
    const codigoBarras = extrairCodigoBarras(corpo);

    return {
      tipo: this.decidirTipo(p.assunto, corpo, inst.tipoPadrao),
      descricao: p.assunto.trim(),
      instituicao: inst.nome,
      valor,
      dataVencimento: data.data ?? p.recebidoEm,
      dataEncontrada: data.data !== null,
      codigoBarras,
    };
  }

  /** Preenche só o que falta (valor null / data não encontrada) com texto do PDF anexo. Nunca
   *  sobrescreve o que já veio do corpo. */
  complementarComTexto(
    parsed: ParsedLancamento,
    texto: string | null,
    recebidoEm: Date,
  ): ParsedLancamento {
    if (!texto) return parsed;
    const t = normalizar(texto);
    const out = { ...parsed };
    if (out.valor === null) out.valor = extrairValor(t).valor;
    if (!out.dataEncontrada) {
      const d = extrairDataVencimento(t, recebidoEm);
      if (d.data) {
        out.dataVencimento = d.data;
        out.dataEncontrada = true;
      }
    }
    if (out.codigoBarras === null) out.codigoBarras = extrairCodigoBarras(t);
    return out;
  }

  private decidirTipo(
    assunto: string,
    corpo: string,
    tipoPadrao: 'CARTAO' | 'OUTRO' | undefined,
  ): TipoLancamentoParser {
    if (tipoPadrao === 'OUTRO') return 'DESPESA';
    const a = normalizar(assunto);
    const cabeca = corpo.slice(0, CABECA_TIPO);
    if (isCardInvoiceSubject(a)) return 'FATURA_CARTAO';
    if (CARTAO_PERTO_DE_FATURA_RE.test(cabeca)) return 'FATURA_CARTAO';
    if (
      tipoPadrao === 'CARTAO' &&
      ASSUNTO_TEM_FATURA_RE.test(a) &&
      !PRODUTO_NAO_CARTAO_RE.test(a)
    )
      return 'FATURA_CARTAO';
    if (
      BANDEIRA_PERTO_DE_FATURA_RE.test(a) ||
      BANDEIRA_PERTO_DE_FATURA_RE.test(cabeca)
    )
      return 'FATURA_CARTAO';
    return 'DESPESA';
  }
}
