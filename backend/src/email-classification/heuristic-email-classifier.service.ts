import { Injectable } from '@nestjs/common';
import {
  EmailClassification,
  EmailClassificationContext,
  EmailClassifier,
  EmailToClassify,
} from './email-classifier.interface';

// 'importante' is deliberately excluded: it's too broad to fix with a word boundary alone
// ("informação importante" in a marketing footer is still a real match, just not a useful
// urgency signal), and — since nothing in this app ever sets plano='pro' — this heuristic is
// the ONLY classifier that ever runs in production, so every false positive here becomes a
// PRECISA_ATENCAO email that drives the aggregated push notification.
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
    const temPalavraChave = PALAVRAS_CHAVE_URGENTES.some(
      (palavra) => containsWholeWord(email.assunto, palavra) || containsWholeWord(email.corpo, palavra),
    );

    return {
      categoria: temPalavraChave ? 'PRECISA_ATENCAO' : 'PODE_ESPERAR',
      resumoCurto: this.truncate(email.assunto),
    };
  }

  private truncate(subject: string): string {
    if (subject.length <= RESUMO_MAX_LENGTH) return subject;
    return `${subject.slice(0, RESUMO_MAX_LENGTH - 3)}...`;
  }
}
