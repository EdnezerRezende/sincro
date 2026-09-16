import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { GmailApiClient } from '../../gmail/gmail-api-client.service';
import { ClasseErroGmail, classificarErroGmail, gmailMensagemNaoEncontrada } from '../../gmail/gmail-error.util';
import { EmailFinanceRegexParserService, ParsedLancamento } from './email-finance-regex-parser.service';
import { triagem } from './finance-email-detector';

export interface EmailParaProcessar { gmailMessageId: string; remetente: string; assunto: string; recebidoEm: Date }
export interface ResultadoProcessamento {
  transitorio: boolean;
  classe: ClasseErroGmail | null;
  acao: 'criado' | 'atualizado' | 'removido' | 'nada' | 'erro';
}

const FILTRO_MAQUINA = { origem: 'EMAIL_PARSER' as const, status: 'PENDENTE_REVISAO' as const };

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

  async processar(userId: string, refreshToken: string, email: EmailParaProcessar, opts: { marcado: boolean }): Promise<ResultadoProcessamento> {
    try {
      const t = triagem(email.remetente, email.assunto, { marcado: opts.marcado });
      if (t.nivel === 'nao') { await this.removerLancamentoDaMaquina(userId, email.gmailMessageId); return this.ok('removido'); }

      const { texto, anexos } = await this.gmail.fetchFullBodyComAnexos(refreshToken, email.gmailMessageId);
      let parsed = this.parser.parse({ remetente: email.remetente, assunto: email.assunto, corpo: texto, recebidoEm: email.recebidoEm, triagem: t, anexos });
      if (!parsed) { await this.removerLancamentoDaMaquina(userId, email.gmailMessageId); return this.ok('removido'); }

      // Consulta o lançamento antes do PDF: se já existir e não for da máquina (revisado/ignorado
      // pelo usuário, ou criado manualmente), não há por que baixar o PDF — ele só serviria para
      // complementar um registro que de qualquer forma não será escrito.
      const existente = await this.prisma.lancamentoFinanceiro.findUnique({
        where: { userId_emailMessageId: { userId, emailMessageId: email.gmailMessageId } },
      });
      if (existente && (existente.origem !== 'EMAIL_PARSER' || existente.status !== 'PENDENTE_REVISAO')) {
        return this.ok('nada');
      }

      if (parsed.valor === null || !parsed.dataEncontrada) {
        const pdf = GmailApiClient.escolherPdf(anexos);
        if (pdf) {
          const textoPdf = await this.gmail.fetchPdfAttachmentText(refreshToken, email.gmailMessageId, pdf);
          parsed = this.parser.complementarComTexto(parsed, textoPdf, email.recebidoEm);
        }
      }
      return await this.gravar(userId, email.gmailMessageId, parsed, existente);
    } catch (error) {
      const classe = classificarErroGmail(error);
      if (classe === 'permanente' && gmailMensagemNaoEncontrada(error)) {
        try {
          await this.removerLancamentoDaMaquina(userId, email.gmailMessageId);
        } catch (removalError) {
          this.logger.error(
            `Failed to remove finance entry for message ${email.gmailMessageId} after 404`,
            removalError as Error,
          );
          return { transitorio: false, classe: 'permanente', acao: 'erro' };
        }
        return { transitorio: false, classe, acao: 'removido' };
      }
      const log = classe === 'permanente' ? 'error' : 'warn';
      this.logger[log](`Finance processing failed for message ${email.gmailMessageId} (${classe})`, error as Error);
      return { transitorio: classe !== 'permanente', classe, acao: 'erro' };
    }
  }

  async removerLancamentoDaMaquina(userId: string, emailMessageId: string): Promise<void> {
    await this.prisma.lancamentoFinanceiro.deleteMany({ where: { userId, emailMessageId, ...FILTRO_MAQUINA } });
  }

  /** `existente` já veio de `processar` (uma única consulta por chamada, feita antes do PDF) —
   *  aqui só decide o que fazer com ele. */
  private async gravar(
    userId: string,
    emailMessageId: string,
    parsed: ParsedLancamento,
    existente: { origem: string; status: string } | null,
  ): Promise<ResultadoProcessamento> {
    const campos = {
      tipo: parsed.tipo, descricao: parsed.descricao, instituicao: parsed.instituicao, valor: parsed.valor,
      dataVencimento: parsed.dataVencimento, dataCompetencia: parsed.dataVencimento, codigoBarras: parsed.codigoBarras,
    };
    if (existente) {
      if (existente.origem !== 'EMAIL_PARSER' || existente.status !== 'PENDENTE_REVISAO') return this.ok('nada');
      await this.prisma.lancamentoFinanceiro.updateMany({ where: { userId, emailMessageId, ...FILTRO_MAQUINA }, data: campos });
      return this.ok('atualizado');
    }
    try {
      await this.prisma.lancamentoFinanceiro.create({ data: { userId, emailMessageId, status: 'PENDENTE_REVISAO', origem: 'EMAIL_PARSER', ...campos } });
      return this.ok('criado');
    } catch (error) {
      if ((error as { code?: string } | null)?.code === 'P2002') return this.ok('nada');
      throw error;
    }
  }

  private ok(acao: ResultadoProcessamento['acao']): ResultadoProcessamento {
    return { transitorio: false, classe: null, acao };
  }
}
