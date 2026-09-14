import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { isCardInvoiceSubject, isSettledPaymentSubject } from './invoice-subject-patterns';

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
  /** Whether an unqualified fatura-lifecycle subject (common invoice-notification phrasing —
   *  "fechou"/"fechada"/"disponível"/"gerada"/"emitida", no explicit "cartão" needed) from THIS
   *  sender defaults to FATURA_CARTAO. Card issuers (Nubank, Itaú, Inter, Bradesco, C6) do — see
   *  `FATURA_LIFECYCLE_RE`. Telecom/utility billers (Claro, Vivo, Enel) don't: their "fatura" is
   *  a phone/energy bill, so it must stay DESPESA unless the subject explicitly says "cartão"
   *  (see `isCardInvoiceSubject`). Getting this wrong flips a DESPESA (only counted against
   *  Saldo Livre within its cycle window) into a FATURA_CARTAO (always subtracted in full) —
   *  see `FinanceSummaryController`. */
  tipoPadrao: 'CARTAO' | 'OUTRO';
}

const INSTITUTION_MAP: InstitutionEntry[] = [
  { domain: 'nubank.com.br', nome: 'Nubank', tipoPadrao: 'CARTAO' },
  { domain: 'itau.com.br', nome: 'Itaú', tipoPadrao: 'CARTAO' },
  { domain: 'bancointer.com.br', nome: 'Inter', tipoPadrao: 'CARTAO' },
  { domain: 'bradesco.com.br', nome: 'Bradesco', tipoPadrao: 'CARTAO' },
  { domain: 'c6bank.com.br', nome: 'C6 Bank', tipoPadrao: 'CARTAO' },
  { domain: 'claro.com.br', nome: 'Claro', tipoPadrao: 'OUTRO' },
  { domain: 'vivo.com.br', nome: 'Vivo', tipoPadrao: 'OUTRO' },
  { domain: 'enel.com.br', nome: 'Enel', tipoPadrao: 'OUTRO' },
];

// Thousand separator is OPTIONAL: `\d{1,3}(?:\.\d{3})*` alone requires either a bare 1-3 digit
// integer part or one broken into dot-groups — a 4+ digit amount with NO grouping dots at all
// ("R$ 2480,35", which real invoices do send) matched neither shape and silently produced
// valor:null. The `|\d+` alternative accepts any run of digits as a fallback.
const CURRENCY_PATTERN = String.raw`R\$\s*((?:\d{1,3}(?:\.\d{3})*|\d+),\d{2})`;
const CURRENCY_RE = new RegExp(CURRENCY_PATTERN);
const VALUE_ANCHORS = [
  /valor\s+a\s+pagar/i,
  /total\s+da\s+fatura/i,
  /total\s+a\s+pagar/i,
  /valor\s+da\s+fatura/i,
  /valor\s+total/i,
];

// Numeric date accepts a 1-2 digit day/month and a 2- or 4-digit year ("5/9/26", "05/09/2026")
// — real Brazilian billing e-mails aren't consistent about zero-padding or 4-digit years, and
// the earlier zero-padded-only, 4-digit-only pattern silently dropped otherwise-legitimate
// invoices whose date just wasn't formatted exactly that way.
// Year alternation tries 4-digit FIRST: with (\d{2}|\d{4}), a 4-digit year like "2026" would
// match the \d{2} branch against just its first two digits ("20"), silently truncating every
// 4-digit year to a wrong 2-digit one (2026 -> 2020).
const DATE_NUMERIC_RE = /(\d{1,2})\/(\d{1,2})\/(\d{4}|\d{2})/;
const DATE_ISO_RE = /(\d{4})-(\d{2})-(\d{2})/;
const MONTHS = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];
const DATE_EXTENSO_RE = new RegExp(
  String.raw`(\d{1,2})\s+de\s+(${MONTHS.join('|')})\s+de\s+(\d{4})`,
  'i',
);
// Lines carrying one of these are trusted as the actual due date, not just any date the body
// happens to mention (a promotional "campanha válida até 31/12" is a date, not a due date).
const DATE_ANCHORS = [/vencimento/i, /vence\s+(em|dia)/i, /pagar\s+at[ée]/i, /pague\s+at[ée]/i];

const BOLETO_47_RE = /^\d{5}\.\d{5}\s\d{5}\.\d{6}\s\d{5}\.\d{6}\s\d\s\d{14}$/m;
const CONCESSIONARIA_48_RE = /^\d{11}-\d\s\d{11}-\d\s\d{11}-\d\s\d{11}-\d$/m;

/** Used only to decide tipo for a sender ALREADY confirmed as a card issuer via `tipoPadrao`
 *  ('CARTAO') — never for `matches()`/eligibility, where an unqualified "fatura" is exactly the
 *  false-positive surface `isCardInvoiceSubject` exists to avoid. Scoping it behind a confirmed
 *  card-issuing institution is what makes trusting a bare lifecycle word here safe.
 *
 *  Requires "sua"/"a" immediately before "fatura" (i.e. the sender's OWN invoice, not just any
 *  mention of the word): a promotional "Nova função: fatura em PDF já disponível" or
 *  "Parcelamento da fatura agora disponível no app" must stay DESPESA, not become FATURA_CARTAO
 *  — they're announcements ABOUT the fatura feature, not the invoice-ready notification itself. */
const FATURA_LIFECYCLE_RE = /\b(?:sua|a)\s+faturas?\s.{0,15}(fechou|fechada|dispon[ií]vel|gerada|emitida)/i;

@Injectable()
export class EmailFinanceRegexParserService {
  private readonly logger = new Logger(EmailFinanceRegexParserService.name);

  constructor(private readonly prisma: PrismaService) {}

  matches(remetente: string, assunto: string): boolean {
    // A payment-confirmation e-mail (already paid, e.g. "Recibo: pagamento da fatura
    // confirmado") must never become a new pending lançamento, no matter how invoice-like the
    // rest of the subject looks or whether the sender is a mapped institution.
    if (isSettledPaymentSubject(assunto)) return false;
    return this.getInstitutionEntry(remetente) !== null || isCardInvoiceSubject(assunto);
  }

  parse(params: {
    remetente: string;
    assunto: string;
    corpo: string;
    recebidoEm: Date;
  }): ParsedLancamento | null {
    if (!this.matches(params.remetente, params.assunto)) return null;
    const institutionEntry = this.getInstitutionEntry(params.remetente);
    const instituicao = institutionEntry?.nome ?? this.deriveInstituicaoFromDomain(params.remetente) ?? 'Desconhecida';

    const { valor, anchored: valorAncorado } = this.extractValor(params.corpo);
    const codigoBarras = this.extractCodigoBarras(params.corpo);
    const { data: dataVencimento, anchored: dataAncorada } = this.extractDataVencimento(
      params.corpo,
      params.recebidoEm,
    );

    // Gated on `isCardInvoiceSubject` for anyone who ISN'T a known non-card institution, not on
    // `!institutionEntry`: a MAPPED sender's marketing address is still that sender's own domain
    // (e.g. `marketing@nubank.com.br`), so "Parcele a fatura do seu cartão em até 12x" from a
    // real Nubank domain is just as much an ad as the same subject from an unmapped one — the
    // institution allowlist vouches for the DOMAIN being genuinely Nubank, not for every subject
    // line Nubank's marketing team sends being an actual invoice notification. Whenever the
    // subject itself is what makes this look like a card invoice, an ANCHORED body signal (a
    // line explicitly labeled "valor a pagar"/"vencimento"/etc., or a barcode) is required — not
    // just any currency or date mention anywhere in the body, which a promotional e-mail ("a
    // partir de R$ 99,90", "campanha válida até 31/12") would also satisfy. Without this, the
    // subject alone is the only real signal this is an invoice at all, and refusing to create a
    // lançamento avoids fabricating a pending entry — with a plausible-looking but made-up
    // value/date — from what is likely just an ad.
    //
    // A sender matched ONLY through institution trust (no "cartão" in the subject, e.g.
    // Nubank's "Sua fatura fechou") is unaffected — that path never relied on the subject
    // content at all. A known NON-card institution (Vivo/Enel, `tipoPadrao === 'OUTRO'`) is also
    // exempt: `ehFaturaCartaoPorAssunto` below can never turn their tipo into FATURA_CARTAO
    // regardless of what the subject says, so there is nothing for this guard to protect against
    // for them — blocking their entry entirely would just regress the long-standing,
    // already-tested behavior of always staging a best-effort (possibly null-valor) DESPESA for
    // any mapped, trusted domain.
    if (institutionEntry?.tipoPadrao !== 'OUTRO' && isCardInvoiceSubject(params.assunto)) {
      const temSinalTransacionalAncorado = valorAncorado || codigoBarras !== null || dataAncorada;
      if (!temSinalTransacionalAncorado) return null;
    }

    const ehFaturaCartaoPorInstituicaoPadrao =
      institutionEntry?.tipoPadrao === 'CARTAO' && FATURA_LIFECYCLE_RE.test(params.assunto);

    // A known NON-card institution (Vivo, Enel: `tipoPadrao === 'OUTRO'`) wins over a subject
    // that merely mentions "cartão" as a PAYMENT METHOD for that phone/energy bill ("Sua fatura
    // Vivo chegou: pague no cartão de crédito") — the invoice itself is still a phone/energy
    // bill, not a credit-card invoice, no matter which payment method the subject advertises.
    const ehFaturaCartaoPorAssunto = institutionEntry?.tipoPadrao !== 'OUTRO' && isCardInvoiceSubject(params.assunto);

    return {
      tipo: ehFaturaCartaoPorAssunto || ehFaturaCartaoPorInstituicaoPadrao ? 'FATURA_CARTAO' : 'DESPESA',
      descricao: params.assunto.trim(),
      instituicao,
      valor,
      dataVencimento,
      codigoBarras,
    };
  }

  async processEmail(
    userId: string,
    email: { gmailMessageId: string; remetente: string; assunto: string; recebidoEm: Date },
    corpoCompleto: string,
  ): Promise<void> {
    const existing = await this.prisma.lancamentoFinanceiro.findUnique({
      where: { userId_emailMessageId: { userId, emailMessageId: email.gmailMessageId } },
    });
    if (existing) return;

    const parsed = this.parse({
      remetente: email.remetente,
      assunto: email.assunto,
      corpo: corpoCompleto,
      recebidoEm: email.recebidoEm,
    });
    if (!parsed) return;

    try {
      await this.prisma.lancamentoFinanceiro.create({
        data: {
          userId,
          tipo: parsed.tipo,
          descricao: parsed.descricao,
          instituicao: parsed.instituicao,
          valor: parsed.valor,
          dataVencimento: parsed.dataVencimento,
          dataCompetencia: parsed.dataVencimento,
          status: 'PENDENTE_REVISAO',
          origem: 'EMAIL_PARSER',
          emailMessageId: email.gmailMessageId,
          codigoBarras: parsed.codigoBarras,
        },
      });
    } catch (error) {
      if ((error as { code?: string } | null)?.code === 'P2002') {
        this.logger.warn(
          `Message ${email.gmailMessageId} was already staged by a concurrent run, skipping (race-safe dedup)`,
        );
        return;
      }
      throw error;
    }
  }

  private getInstitutionEntry(remetente: string): InstitutionEntry | null {
    const lower = remetente.toLowerCase();
    return INSTITUTION_MAP.find((entry) => lower.includes(entry.domain)) ?? null;
  }

  /** Best-effort institution name for a sender OUTSIDE the curated `INSTITUTION_MAP` — used once
   *  `matches()` also accepts generic card-invoice subjects from unmapped senders (see
   *  `isCardInvoiceSubject`), so `instituicao` isn't left empty. Extracts the address from
   *  `Nome <endereço@dominio>` (or a bare address) rather than assuming it sits at the end of the
   *  string — a trailing comment (`"Nome <a@b.com> (não responda)"`) or a second address after a
   *  comma would otherwise be picked up instead. Then strips the public-suffix labels
   *  ("com"/"com.br"/"co.uk"/...) and skips generic mailer/subdomain labels ("mail", "e",
   *  "notificacoes", ...) to land on the registrable brand label (`mail.meubanco.com` ->
   *  "Meubanco", not "Mail"). */
  private deriveInstituicaoFromDomain(remetente: string): string | null {
    const address = this.extractEmailAddress(remetente);
    if (!address) return null;
    const domain = address.slice(address.lastIndexOf('@') + 1).toLowerCase();
    const labels = domain.split('.');
    if (labels.length < 2) return null;

    const GENERIC_SECOND_LEVEL = new Set(['com', 'net', 'org', 'gov', 'edu', 'co']);
    const GENERIC_SUBDOMAIN_LABELS = new Set([
      'mail', 'email', 'e', 'news', 'notificacoes', 'notificacao', 'mailer', 'info', 'no-reply', 'noreply',
    ]);

    const publicSuffixLength =
      labels.length > 2 && GENERIC_SECOND_LEVEL.has(labels[labels.length - 2]) ? 2 : 1;
    const candidates = labels.slice(0, labels.length - publicSuffixLength);
    if (candidates.length === 0) return null;

    const significant = candidates.find((label) => !GENERIC_SUBDOMAIN_LABELS.has(label)) ?? candidates[candidates.length - 1];
    if (!significant) return null;
    return significant.charAt(0).toUpperCase() + significant.slice(1);
  }

  private extractEmailAddress(remetente: string): string | null {
    const angleMatch = remetente.match(/<([^<>]+)>/);
    const candidate = (angleMatch ? angleMatch[1] : remetente).trim();
    const emailMatch = candidate.match(/[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}/i);
    return emailMatch ? emailMatch[0] : null;
  }

  /** `anchored: true` means the value was found on (or on the line right after) a line
   *  explicitly labeled as a due amount (`VALUE_ANCHORS`) — trusted as the REAL invoice value.
   *  `anchored: false` means it was found only via the last-resort fallback (exactly one
   *  currency mention anywhere in the body, no label at all) — good enough for a mapped,
   *  trusted institution's best-effort extraction, but NOT enough on its own to prove a
   *  card-invoice-subject match is a real invoice (a promotional "a partir de R$ 99,90" is a
   *  currency mention too). See the `isCardInvoiceSubject(...)` guard in `parse()`. */
  private extractValor(body: string): { valor: number | null; anchored: boolean } {
    const lines = body.split(/\r?\n/);
    for (const anchor of VALUE_ANCHORS) {
      const globalAnchor = new RegExp(anchor.source, anchor.flags.includes('g') ? anchor.flags : `${anchor.flags}g`);
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        const anchorMatches = [...line.matchAll(globalAnchor)];
        if (anchorMatches.length === 0) continue;
        for (const anchorMatch of anchorMatches) {
          // Search only AFTER the anchor label's own position, not the whole line — an HTML
          // table row collapsed to one line ("Pagamento mínimo R$ 123,45 Total da fatura
          // R$ 1.234,56") would otherwise let an unrelated earlier currency on the SAME line
          // (the minimum payment) be picked up for a DIFFERENT anchor (the total) matched later
          // in that line. `matchAll` (not just the first occurrence) matters when the SAME
          // anchor phrase appears twice on one line ("Valor a pagar após o vencimento R$ X
          // Valor a pagar até o vencimento R$ Y") — the "após o vencimento" occurrence is a
          // late-fee amount, explicitly skipped below, so the loop must reach the second one.
          const afterAnchor = line.slice(anchorMatch.index + anchorMatch[0].length);
          if (/^\s*ap[oó]s\b/i.test(afterAnchor)) continue;
          const match = afterAnchor.match(CURRENCY_RE);
          if (match) return { valor: this.parseBrCurrency(match[1]), anchored: true };
        }
        // The anchor was found but no usable value followed it on the SAME line — common when
        // an HTML `<div>label</div><div>value</div>` pair collapses to one line each instead of
        // staying on one line together. Check the very next line before giving up on this
        // anchor entirely.
        const nextLine = lines[i + 1];
        if (nextLine !== undefined) {
          const match = nextLine.match(CURRENCY_RE);
          if (match) return { valor: this.parseBrCurrency(match[1]), anchored: true };
        }
      }
    }
    const allMatches = [...body.matchAll(new RegExp(CURRENCY_PATTERN, 'g'))];
    if (allMatches.length === 1) return { valor: this.parseBrCurrency(allMatches[0][1]), anchored: false };
    return { valor: null, anchored: false };
  }

  private parseBrCurrency(raw: string): number {
    return parseFloat(raw.replace(/\./g, '').replace(',', '.'));
  }

  private parseNumericDate(dd: string, mm: string, yearRaw: string): Date {
    const yyyy = yearRaw.length === 2 ? 2000 + Number(yearRaw) : Number(yearRaw);
    return new Date(Date.UTC(yyyy, Number(mm) - 1, Number(dd)));
  }

  /** `anchored: true` means the date was found on (or on the line right after) a line
   *  explicitly labeled as a due date (`DATE_ANCHORS` — "vencimento", "vence em/dia",
   *  "pagar/pague até"). `anchored: false` means it fell back to the first date mentioned
   *  ANYWHERE in the body with no label — good enough for a mapped, trusted institution, but a
   *  promotional "campanha válida até 31/12" is a date too, so it's not enough on its own to
   *  prove a card-invoice-subject match is a real invoice. See the `isCardInvoiceSubject(...)`
   *  guard in `parse()`. */
  private extractDataVencimento(
    body: string,
    recebidoEm: Date,
  ): { data: Date; encontradaNoCorpo: boolean; anchored: boolean } {
    const lines = body.split(/\r?\n/);
    for (const anchor of DATE_ANCHORS) {
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        const anchorMatch = line.match(anchor);
        if (!anchorMatch || anchorMatch.index === undefined) continue;
        // Same reasoning as `extractValor`: search only AFTER the anchor label's position, not
        // the whole line — a real invoice's HTML table row, once collapsed to plain text by
        // `GmailApiClient.htmlParaTextoLegivel`, can read "Fechamento 28/09/2026 Vencimento
        // 10/10/2026" on one line; matching from the start of the line would grab the closing
        // date (28/09) instead of the due date that follows "Vencimento".
        const afterAnchor = line.slice(anchorMatch.index + anchorMatch[0].length);
        const found = this.matchDateIn(afterAnchor);
        if (found) return { data: found, encontradaNoCorpo: true, anchored: true };
        // The anchor was found but no usable date followed it on the SAME line — common when an
        // HTML `<div>label</div><div>value</div>` pair collapses to one line each. Check the
        // very next line before giving up on this anchor entirely.
        const nextLine = lines[i + 1];
        if (nextLine !== undefined) {
          const foundNext = this.matchDateIn(nextLine);
          if (foundNext) return { data: foundNext, encontradaNoCorpo: true, anchored: true };
        }
      }
    }

    const fallback = this.matchDateIn(body);
    if (fallback) return { data: fallback, encontradaNoCorpo: true, anchored: false };
    return { data: recebidoEm, encontradaNoCorpo: false, anchored: false };
  }

  private matchDateIn(text: string): Date | null {
    const numeric = text.match(DATE_NUMERIC_RE);
    if (numeric) {
      const [, dd, mm, yyyy] = numeric;
      return this.parseNumericDate(dd, mm, yyyy);
    }
    const iso = text.match(DATE_ISO_RE);
    if (iso) {
      const [, yyyy, mm, dd] = iso;
      return new Date(Date.UTC(Number(yyyy), Number(mm) - 1, Number(dd)));
    }
    const extenso = text.match(DATE_EXTENSO_RE);
    if (extenso) {
      const [, dd, mesNome, yyyy] = extenso;
      const mesIndex = MONTHS.indexOf(mesNome.toLowerCase());
      return new Date(Date.UTC(Number(yyyy), mesIndex, Number(dd)));
    }
    return null;
  }

  private extractCodigoBarras(body: string): string | null {
    const boleto = body.match(BOLETO_47_RE);
    if (boleto) return boleto[0];
    const concessionaria = body.match(CONCESSIONARIA_48_RE);
    if (concessionaria) return concessionaria[0];
    return null;
  }
}
