import { Injectable } from '@nestjs/common';
import {
  EmailClassification,
  EmailClassificationContext,
  EmailClassifier,
  EmailToClassify,
} from './email-classifier.interface';
import { isCardInvoiceSubject, isSettledPaymentSubject } from '../financas/parser/invoice-subject-patterns';

// 'importante' is deliberately excluded: it's too broad to fix with a word boundary alone
// ("informação importante" in a marketing footer is still a real match, just not a useful
// urgency signal), and — since nothing in this app ever sets plano='pro' — this heuristic is
// the ONLY classifier that ever runs in production, so every false positive here becomes a
// PRECISA_ATENCAO email that drives the aggregated push notification.
// A bare 'fatura' is excluded for the same reason: it's a topic word, not an urgency signal —
// it appears just as often in marketing ("Parcele sua fatura em 12x") and payment receipts
// ("Sua fatura anterior foi quitada") as in a real pending invoice. Card-invoice urgency is
// instead detected via `isCardInvoiceSubject` below, the same tightly-scoped
// "fatura"+"cartão" check the finance parser uses — so a subject like "A fatura do seu cartão
// chegou" still surfaces as needing attention even when it never says "vencimento"/"vence"
// verbatim, without the false-positive blast radius of the bare noun.
const PALAVRAS_CHAVE_URGENTES = ['urgente', 'prazo', 'vencimento', 'vence', 'ação necessária'];
const RESUMO_MAX_LENGTH = 100;

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/**
 * Whole-word (or whole-phrase) match, case-insensitive, safe for Portuguese accented
 * characters. Plain \b behaves inconsistently around accented letters (â, ç, ã, ...) because
 * JS's classic \b is defined in terms of ASCII \w — so this uses Unicode-aware lookaround on
 * \p{L}/\p{N} instead of \b. This is what stops 'vence' from matching inside 'convencer': the
 * character immediately before the match ('n') is a letter, so the lookbehind fails.
 */
function containsWholeWord(text: string, phrase: string): boolean {
  const pattern = new RegExp(`(?<![\\p{L}\\p{N}])${escapeRegExp(phrase)}(?![\\p{L}\\p{N}])`, 'iu');
  return pattern.test(text);
}

@Injectable()
export class HeuristicEmailClassifier implements EmailClassifier {
  async classify(email: EmailToClassify, _context: EmailClassificationContext): Promise<EmailClassification> {
    // A settled-payment SUBJECT (e.g. "Recibo: pagamento da fatura confirmado") overrides
    // everything else, including the urgency-keyword list: a receipt is inherently non-urgent
    // regardless of what else the body mentions in passing (a next-cycle due date, a "vencimento"
    // in unrelated boilerplate). Checked on the subject only, never the body — Brazilian billing
    // e-mails routinely carry conditional/boilerplate phrasing in the body ("caso o pagamento já
    // tenha sido confirmado, desconsidere", "o comprovante de pagamento fica disponível por 90
    // dias") that would wrongly veto a genuinely pending invoice if the body were scanned too.
    if (isSettledPaymentSubject(email.assunto)) {
      return { categoria: 'PODE_ESPERAR', resumoCurto: this.truncate(email.assunto) };
    }

    const temPalavraChave = PALAVRAS_CHAVE_URGENTES.some(
      (palavra) => containsWholeWord(email.assunto, palavra) || containsWholeWord(email.corpo, palavra),
    );
    // Checked on the SUBJECT only, never the body: a promotional footer routinely contains the
    // phrase ("parcele no cartão... fatura do seu cartão, sem juros") without the e-mail being
    // about an invoice at all — see the doc comment on `isCardInvoiceSubject`.
    const ehFaturaDeCartaoPendente = isCardInvoiceSubject(email.assunto);

    return {
      categoria: temPalavraChave || ehFaturaDeCartaoPendente ? 'PRECISA_ATENCAO' : 'PODE_ESPERAR',
      resumoCurto: this.truncate(email.assunto),
    };
  }

  private truncate(subject: string): string {
    if (subject.length <= RESUMO_MAX_LENGTH) return subject;
    return `${subject.slice(0, RESUMO_MAX_LENGTH - 3)}...`;
  }
}
