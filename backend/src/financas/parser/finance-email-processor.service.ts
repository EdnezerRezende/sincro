import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { GmailApiClient } from '../../gmail/gmail-api-client.service';
import {
  ClasseErroGmail,
  classificarErroGmail,
  gmailMensagemNaoEncontrada,
  statusHttpDoErroGmail,
} from '../../gmail/gmail-error.util';
import {
  EmailFinanceRegexParserService,
  ParsedLancamento,
} from './email-finance-regex-parser.service';
import { ResultadoTriagem, triagem } from './finance-email-detector';

export interface EmailParaProcessar {
  gmailMessageId: string;
  remetente: string;
  assunto: string;
  recebidoEm: Date;
}
export interface ResultadoProcessamento {
  transitorio: boolean;
  classe: ClasseErroGmail | null;
  acao: 'criado' | 'atualizado' | 'removido' | 'nada' | 'erro';
}

const ASSUNTO_LOG_MAX = 80;
/** Teto da linha de auditoria inteira; o assunto (serializado como JSON no fim) é o que cede. */
const LINHA_MAX = 300;
const CONTROLES_RE = /[\p{Cc}\p{Cf}\p{Zl}\p{Zp}\s]+/gu;
type NivelLog = 'log' | 'warn' | 'error';

/** Nunca o objeto de erro: um GaxiosError carrega `config.headers.Authorization` (o bearer token
 *  do usuário) e o ConsoleLogger do Nest o imprime inteiro. Só classe, código e status. */
function descreverErro(error: unknown): string {
  const e = error as {
    constructor?: { name?: string };
    name?: string;
    message?: unknown;
    code?: unknown;
  } | null;
  const nomeCtor = e?.constructor?.name;
  const nome =
    (nomeCtor && nomeCtor !== 'Object' ? nomeCtor : e?.name) ?? typeof error;
  const code =
    typeof e?.code === 'string' || typeof e?.code === 'number'
      ? String(e.code)
      : undefined;
  const status = statusHttpDoErroGmail(error);
  // `{code: 503, response: {status: 503}}` não vira "[Error 503 HTTP 503]".
  const codeUtil =
    code !== undefined && code !== String(status) ? code : undefined;
  return `[${[nome, codeUtil, status !== undefined ? `HTTP ${status}` : undefined].filter(Boolean).join(' ')}]`;
}
const MENSAGEM_ERRO_MAX = 160;
/** Mensagem do erro achatada e cortada por code point (não por unidade UTF-16: um emoji na
 *  borda viraria surrogate solitário e a linha deixaria de ser UTF-8 válido). */
function mensagemSegura(error: unknown): string {
  const m = (error as { message?: unknown } | null)?.message;
  if (typeof m !== 'string') return '';
  const pontos = Array.from(m.replace(CONTROLES_RE, ' ').trim());
  return pontos.length > MENSAGEM_ERRO_MAX
    ? `${pontos.slice(0, MENSAGEM_ERRO_MAX - 1).join('')}…`
    : pontos.join('');
}
const FILTRO_MAQUINA = {
  origem: 'EMAIL_PARSER' as const,
  status: 'PENDENTE_REVISAO' as const,
};

/** Ponto único: e-mails novos e reprocessamento passam por aqui. Nunca lança — devolve a classe do erro
 *  para o chamador decidir o carimbo de versão. */
@Injectable()
export class FinanceEmailProcessor {
  private readonly logger = new Logger(FinanceEmailProcessor.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly gmail: GmailApiClient,
    private readonly parser: EmailFinanceRegexParserService,
  ) {}

  /** Uma linha por e-mail avaliado, com o porquê e o DESFECHO REAL — emitida DEPOIS da escrita
   *  (ou do erro), nunca antes, sempre como `→ <acao>: <detalhe>` com a MESMA `acao` que
   *  `processar` devolve: é o que permite auditar em produção por que um e-mail de cobrança não
   *  virou lançamento (veto, sinal fraco sem evidência, já revisado, corrida, Gmail fora...).
   *  Carimba `userId` como as demais linhas do EmailSyncService e sai no nível da severidade do
   *  desfecho (erro transitório em warn, permanente em error). Só o assunto entra — nunca corpo
   *  nem token — achatado numa linha (qualquer controle/separador Unicode vira espaço: um
   *  Subject hostil poderia forjar um registro, CWE-117, ou injetar escape ANSI), cortado por
   *  code point (não parte emoji) e serializado como JSON no FIM da linha, para que aspas e `|`
   *  não forjem campos. A linha inteira respeita `LINHA_MAX`: se o assunto serializado não
   *  couber (aspas/barras dobram no JSON), ele encolhe até caber. */
  private logDecisao(
    userId: string,
    email: EmailParaProcessar,
    t: ResultadoTriagem,
    acao: ResultadoProcessamento['acao'],
    detalhe: string,
    nivel: NivelLog = 'log',
  ): void {
    const motivo = t.motivo ? ` motivo="${t.motivo}"` : '';
    const prefixo =
      `finance user=${userId} msg=${email.gmailMessageId} nivel=${t.nivel} ` +
      `sinais=[${t.sinais.join(',')}]${motivo} → ${acao}: ${detalhe} | assunto=`;
    const assunto =
      email.assunto.replace(CONTROLES_RE, ' ').trim() || '(sem assunto)';
    let pontos = Array.from(assunto);
    let cortado = false;
    if (pontos.length > ASSUNTO_LOG_MAX) {
      pontos = pontos.slice(0, ASSUNTO_LOG_MAX - 1);
      cortado = true;
    }
    const orcamento = Math.max(LINHA_MAX - prefixo.length, 12);
    let serial = JSON.stringify(cortado ? `${pontos.join('')}…` : assunto);
    while (serial.length > orcamento && pontos.length > 1) {
      pontos = pontos.slice(0, -1);
      cortado = true;
      serial = JSON.stringify(`${pontos.join('')}…`);
    }
    this.logger[nivel](prefixo + serial);
  }

  async processar(
    userId: string,
    refreshToken: string,
    email: EmailParaProcessar,
    opts: { marcado: boolean },
  ): Promise<ResultadoProcessamento> {
    // Puro e síncrono: fica fora do try para estar disponível na linha de auditoria do catch.
    const t = triagem(email.remetente, email.assunto, {
      marcado: opts.marcado,
    });
    try {
      if (t.nivel === 'nao') {
        const apagados = await this.removerLancamentoDaMaquina(
          userId,
          email.gmailMessageId,
        );
        this.logDecisao(
          userId,
          email,
          t,
          'removido',
          `descartado na triagem${this.sufixoApagados(apagados)}`,
        );
        return this.ok('removido');
      }

      const { texto, anexos } = await this.gmail.fetchFullBodyComAnexos(
        refreshToken,
        email.gmailMessageId,
      );
      const parse = this.parser.parseDetalhado({
        remetente: email.remetente,
        assunto: email.assunto,
        corpo: texto,
        recebidoEm: email.recebidoEm,
        triagem: t,
        anexos,
      });
      let parsed = parse.lancamento;
      if (!parsed) {
        const apagados = await this.removerLancamentoDaMaquina(
          userId,
          email.gmailMessageId,
        );
        this.logDecisao(
          userId,
          email,
          t,
          'removido',
          `descartado no parser: ${parse.motivo}${this.sufixoApagados(apagados)}`,
        );
        return this.ok('removido');
      }

      // Consulta o lançamento antes do PDF: se já existir e não for da máquina (revisado/ignorado
      // pelo usuário, ou criado manualmente), não há por que baixar o PDF — ele só serviria para
      // complementar um registro que de qualquer forma não será escrito.
      const existente = await this.prisma.lancamentoFinanceiro.findUnique({
        where: {
          userId_emailMessageId: {
            userId,
            emailMessageId: email.gmailMessageId,
          },
        },
      });
      if (
        existente &&
        (existente.origem !== 'EMAIL_PARSER' ||
          existente.status !== 'PENDENTE_REVISAO')
      ) {
        this.logDecisao(
          userId,
          email,
          t,
          'nada',
          `lançamento já ${existente.origem === 'EMAIL_PARSER' ? existente.status.toLowerCase() : 'manual'} (não reavaliado)`,
        );
        return this.ok('nada');
      }

      if (parsed.valor === null || !parsed.dataEncontrada) {
        const pdf = GmailApiClient.escolherPdf(anexos);
        if (pdf) {
          const textoPdf = await this.gmail.fetchPdfAttachmentText(
            refreshToken,
            email.gmailMessageId,
            pdf,
          );
          parsed = this.parser.complementarComTexto(
            parsed,
            textoPdf,
            email.recebidoEm,
          );
        }
      }
      const r = await this.gravar(
        userId,
        email.gmailMessageId,
        parsed,
        existente,
      );
      this.logDecisao(userId, email, t, r.acao, r.detalhe);
      return this.ok(r.acao);
    } catch (error) {
      const classe = classificarErroGmail(error);
      if (classe === 'permanente' && gmailMensagemNaoEncontrada(error)) {
        try {
          const apagados = await this.removerLancamentoDaMaquina(
            userId,
            email.gmailMessageId,
          );
          this.logDecisao(
            userId,
            email,
            t,
            'removido',
            `mensagem não existe mais no Gmail (404)${this.sufixoApagados(apagados)}`,
          );
        } catch (removalError) {
          this.logDiagnostico(
            'error',
            userId,
            email,
            'falha ao apagar lançamento pendente após 404',
            removalError,
          );
          this.logDecisao(
            userId,
            email,
            t,
            'erro',
            `mensagem não existe mais no Gmail (404), mas falhou ao apagar o lançamento pendente ${descreverErro(removalError)}`,
            'error',
          );
          return { transitorio: false, classe: 'permanente', acao: 'erro' };
        }
        return { transitorio: false, classe, acao: 'removido' };
      }
      const transitorio = classe !== 'permanente';
      const nivel: NivelLog = transitorio ? 'warn' : 'error';
      this.logDiagnostico(
        nivel,
        userId,
        email,
        `falha no processamento (${classe})`,
        error,
      );
      this.logDecisao(
        userId,
        email,
        t,
        'erro',
        `${classe} ${descreverErro(error)} ${transitorio ? '(será reprocessado)' : '(permanente — versão carimbada, não volta)'}`,
        nivel,
      );
      return { transitorio, classe, acao: 'erro' };
    }
  }

  private sufixoApagados(apagados: number | undefined): string {
    if (apagados === undefined) return ' (apagados desconhecido)';
    return apagados > 0 ? ', lançamento pendente apagado' : ' (nada a apagar)';
  }

  /** Linha de diagnóstico do erro (irmã da linha de auditoria): mesmo prefixo `finance user= msg=`
   *  e a mensagem do erro serializada como JSON no fim — texto livre no meio da linha (o Prisma
   *  renderiza argumentos na mensagem) casaria num `grep 'finance user='` sem âncora. */
  private logDiagnostico(
    nivel: NivelLog,
    userId: string,
    email: EmailParaProcessar,
    contexto: string,
    error: unknown,
  ): void {
    this.logger[nivel](
      `finance user=${userId} msg=${email.gmailMessageId} ${contexto} ${descreverErro(error)} | mensagem=${JSON.stringify(mensagemSegura(error))}`,
    );
  }

  /** Devolve quantos lançamentos pendentes da máquina foram apagados (0 quando não havia;
   *  `undefined` se o cliente não informou `count` — o Prisma real sempre informa). */
  async removerLancamentoDaMaquina(
    userId: string,
    emailMessageId: string,
  ): Promise<number | undefined> {
    const r = await this.prisma.lancamentoFinanceiro.deleteMany({
      where: { userId, emailMessageId, ...FILTRO_MAQUINA },
    });
    return r?.count;
  }

  /** `existente` já veio de `processar` (uma única consulta por chamada, feita antes do PDF) —
   *  aqui só decide o que fazer com ele. O `detalhe` é o que vai para a linha de auditoria; a
   *  contagem do `updateMany` importa porque o usuário pode ter revisado o lançamento na janela
   *  entre a leitura e a escrita — aí não houve atualização nenhuma. */
  private async gravar(
    userId: string,
    emailMessageId: string,
    parsed: ParsedLancamento,
    existente: { origem: string; status: string } | null,
  ): Promise<{ acao: ResultadoProcessamento['acao']; detalhe: string }> {
    const campos = {
      tipo: parsed.tipo,
      descricao: parsed.descricao,
      instituicao: parsed.instituicao,
      valor: parsed.valor,
      dataVencimento: parsed.dataVencimento,
      dataCompetencia: parsed.dataVencimento,
      codigoBarras: parsed.codigoBarras,
    };
    const resumo = `${parsed.tipo} valor=${parsed.valor ?? 'null'} data=${parsed.dataEncontrada ? 'ok' : 'fallback'}`;
    if (existente) {
      if (
        existente.origem !== 'EMAIL_PARSER' ||
        existente.status !== 'PENDENTE_REVISAO'
      )
        return {
          acao: 'nada',
          detalhe: 'lançamento já revisado (não reavaliado)',
        };
      const r = await this.prisma.lancamentoFinanceiro.updateMany({
        where: { userId, emailMessageId, ...FILTRO_MAQUINA },
        data: campos,
      });
      if (r?.count === 0)
        return {
          acao: 'nada',
          detalhe:
            'lançamento revisado pelo usuário durante o processamento (updateMany=0)',
        };
      // Prisma real sempre traz `count`; sem ele não há prova de escrita — registra a dúvida.
      return {
        acao: 'atualizado',
        detalhe:
          r?.count === undefined ? `${resumo} (count desconhecido)` : resumo,
      };
    }
    try {
      await this.prisma.lancamentoFinanceiro.create({
        data: {
          userId,
          emailMessageId,
          status: 'PENDENTE_REVISAO',
          origem: 'EMAIL_PARSER',
          ...campos,
        },
      });
      return { acao: 'criado', detalhe: resumo };
    } catch (error) {
      if ((error as { code?: string } | null)?.code === 'P2002')
        return { acao: 'nada', detalhe: 'duplicado (corrida P2002)' };
      throw error;
    }
  }

  private ok(acao: ResultadoProcessamento['acao']): ResultadoProcessamento {
    return { transitorio: false, classe: null, acao };
  }
}
