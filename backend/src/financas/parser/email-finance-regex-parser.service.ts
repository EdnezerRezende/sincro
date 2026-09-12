import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

export type TipoLancamentoParser = 'DESPESA' | 'FATURA_CARTAO';

export interface ParsedLancamento {
  tipo: TipoLancamentoParser;
  descricao: string;
  instituicao: string;
  valor: number | null;
  dataVencimento: Date;
  codigoBarras: string | null;
}

interface InstitutionEntry {
  domain: string;
  nome: string;
}

const INSTITUTION_MAP: InstitutionEntry[] = [
  { domain: 'nubank.com.br', nome: 'Nubank' },
  { domain: 'itau.com.br', nome: 'Itaú' },
  { domain: 'bancointer.com.br', nome: 'Inter' },
  { domain: 'bradesco.com.br', nome: 'Bradesco' },
  { domain: 'c6bank.com.br', nome: 'C6 Bank' },
  { domain: 'claro.com.br', nome: 'Claro' },
  { domain: 'vivo.com.br', nome: 'Vivo' },
  { domain: 'enel.com.br', nome: 'Enel' },
];

const CURRENCY_PATTERN = String.raw`R\$\s*([\d]{1,3}(?:\.\d{3})*,\d{2})`;
const CURRENCY_RE = new RegExp(CURRENCY_PATTERN);
const VALUE_ANCHORS = [/valor\s+a\s+pagar/i, /total\s+da\s+fatura/i, /total\s+a\s+pagar/i];

const DATE_NUMERIC_RE = /(\d{2})\/(\d{2})\/(\d{4})/;
const MONTHS = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];
const DATE_EXTENSO_RE = new RegExp(
  String.raw`(\d{1,2})\s+de\s+(${MONTHS.join('|')})\s+de\s+(\d{4})`,
  'i',
);

const BOLETO_47_RE = /^\d{5}\.\d{5}\s\d{5}\.\d{6}\s\d{5}\.\d{6}\s\d\s\d{14}$/m;
const CONCESSIONARIA_48_RE = /^\d{11}-\d\s\d{11}-\d\s\d{11}-\d\s\d{11}-\d$/m;

const FATURA_FECHOU_RE = /fatura\s+fechou/i;

@Injectable()
export class EmailFinanceRegexParserService {
  private readonly logger = new Logger(EmailFinanceRegexParserService.name);

  constructor(private readonly prisma: PrismaService) {}

  matches(remetente: string, _assunto: string): boolean {
    return this.getInstituicao(remetente) !== null;
  }

  parse(params: {
    remetente: string;
    assunto: string;
    corpo: string;
    recebidoEm: Date;
  }): ParsedLancamento | null {
    const instituicao = this.getInstituicao(params.remetente);
    if (!instituicao) return null;

    return {
      tipo: FATURA_FECHOU_RE.test(params.assunto) ? 'FATURA_CARTAO' : 'DESPESA',
      descricao: params.assunto.trim(),
      instituicao,
      valor: this.extractValor(params.corpo),
      dataVencimento: this.extractDataVencimento(params.corpo, params.recebidoEm),
      codigoBarras: this.extractCodigoBarras(params.corpo),
    };
  }

  private getInstituicao(remetente: string): string | null {
    const lower = remetente.toLowerCase();
    const found = INSTITUTION_MAP.find((entry) => lower.includes(entry.domain));
    return found ? found.nome : null;
  }

  private extractValor(body: string): number | null {
    const lines = body.split(/\r?\n/);
    for (const anchor of VALUE_ANCHORS) {
      for (const line of lines) {
        if (anchor.test(line)) {
          const match = line.match(CURRENCY_RE);
          if (match) return this.parseBrCurrency(match[1]);
        }
      }
    }
    const allMatches = [...body.matchAll(new RegExp(CURRENCY_PATTERN, 'g'))];
    if (allMatches.length === 1) return this.parseBrCurrency(allMatches[0][1]);
    return null;
  }

  private parseBrCurrency(raw: string): number {
    return parseFloat(raw.replace(/\./g, '').replace(',', '.'));
  }

  private extractDataVencimento(body: string, recebidoEm: Date): Date {
    const numeric = body.match(DATE_NUMERIC_RE);
    if (numeric) {
      const [, dd, mm, yyyy] = numeric;
      return new Date(Date.UTC(Number(yyyy), Number(mm) - 1, Number(dd)));
    }
    const extenso = body.match(DATE_EXTENSO_RE);
    if (extenso) {
      const [, dd, mesNome, yyyy] = extenso;
      const mesIndex = MONTHS.indexOf(mesNome.toLowerCase());
      return new Date(Date.UTC(Number(yyyy), mesIndex, Number(dd)));
    }
    return recebidoEm;
  }

  private extractCodigoBarras(body: string): string | null {
    const boleto = body.match(BOLETO_47_RE);
    if (boleto) return boleto[0];
    const concessionaria = body.match(CONCESSIONARIA_48_RE);
    if (concessionaria) return concessionaria[0];
    return null;
  }
}
