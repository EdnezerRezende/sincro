/** Subject-line heuristics shared between the finance regex parser and the heuristic e-mail
 *  classifier, so both agree on what counts as a credit-card invoice e-mail worth surfacing.
 *
 *  `isCardInvoiceSubject` is deliberately narrow: it requires "fatura(s)"/"cartão(ões)" to
 *  co-occur, not "fatura" alone. A bare "fatura" also shows up in utility bills ("fatura de
 *  energia"), phone bills, and — much more dangerously — in marketing ("Parcele sua fatura em
 *  12x") and payment receipts ("Recibo: pagamento da sua fatura confirmado"). Matching on
 *  "fatura" alone turned those into fabricated FATURA_CARTAO lançamentos with invented
 *  valor/dataVencimento. Requiring "cartão" nearby keeps the match anchored to what the user
 *  actually asked to detect ("A fatura do seu cartão"). Callers should feed it the SUBJECT
 *  only, not the body — a promotional footer ("parcele no cartão... fatura do seu cartão, sem
 *  juros") can legitimately contain the phrase without the e-mail being about an invoice at all.
 *
 *  `isSettledPaymentSubject` is a hard veto: an e-mail confirming a payment already happened
 *  must never become a new PENDENTE_REVISAO lançamento, regardless of sender or how invoice-like
 *  the rest of the subject looks. It is negation-aware — "sua fatura ainda não foi paga" must
 *  NOT be treated as settled, or a genuinely overdue invoice would be silently dropped instead
 *  of surfaced, which is the opposite of what this whole detector exists to do. */
const FATURA_WORD = 'faturas?';
const CARTAO_WORD = 'cart(?:[ãa]o|[õo]es)';

const CARD_INVOICE_SUBJECT_PATTERNS = [
  new RegExp(`${FATURA_WORD}\\b.{0,25}${CARTAO_WORD}`, 'i'),
  new RegExp(`${CARTAO_WORD}.{0,25}${FATURA_WORD}\\b`, 'i'),
];

// Each pattern's matched span (plus everything before it in the same clause) is checked for a
// negation ("não"/"nunca"/"jamais") before it's trusted as a real settled-payment signal — see
// `isSettledPaymentSubject` below. `quitad[ao]`/`foi\s+pag[ao]` are word-bounded so they don't
// fire inside an unrelated word (a fabricated "Requitada" must not match "quitada"). `recibo`
// alone was dropped: Brazilian boletos routinely print "recibo do sacado" as boilerplate,
// unrelated to whether anything was paid — only "recibo/comprovante de pagamento" counts.
// Active-voice confirmations ("Recebemos/Confirmamos o pagamento...", "Pagamento recebido",
// "Débito automático realizado") and a cancelled/reversed invoice/payment are included
// alongside the passive-voice forms above. The cancellation patterns require "fatura"/
// "pagamento" to be the thing that got cancelled/reversed, appearing BEFORE
// "cancelad[ao]"/"estornad[ao]" — a bare `\bcancelad[ao]\b` word match is too broad: "Débito
// automático cancelado: pague sua fatura" or "Seu cartão foi cancelado — fatura final
// disponível" are about a DIFFERENT thing (the auto-debit, the card) being cancelled while the
// invoice itself is very much still owed, and would otherwise vanish a real pending charge.
const SETTLED_PAYMENT_SUBJECT_PATTERNS = [
  /pagamento\s.{0,35}confirmad[oa]/i,
  /fatura\s.{0,35}confirmad[oa]/i,
  /\bfoi\s+pag[ao]\b/i,
  /\bfatura\s+pag[ao]\b/i,
  // "fatura já paga", "fatura anterior, totalmente paga", "fatura atual está paga": até 3 palavras
  // de um conjunto fechado entre "fatura" e "pag[ao]" — "ainda não" fica fora do conjunto de
  // propósito, para que "fatura ainda não paga" continue NÃO liquidada.
  /\bfatura,?\s+(?:(?:j[áa]|anterior|atual|passada|totalmente|integralmente|est[áa]|foi),?\s+){1,3}pag[ao]\b/i,
  /\bquitad[ao]\b/i,
  /recibo\s+de\s+pagamento/i,
  /comprovante\s+de\s+pagamento/i,
  /\b(recebemos|confirmamos|registramos)\s+(o\s+)?(seu\s+)?pagamento\b/i,
  /\bpagamento\s+recebido\b/i,
  /d[eé]bito\s+autom[aá]tico\s.{0,20}realizado/i,
  /\bfatura\s.{0,20}(cancelad[ao]|estornad[ao])\b/i,
  /\bpagamento\s.{0,20}(cancelad[ao]|estornad[ao])\b/i,
];
// A negation is only trusted when it precedes a settled-RELATED verb stem within a short,
// bounded gap — not "anywhere earlier in the clause". A whitelist of exact reassurance PHRASES
// ("não se preocupe") was tried first and kept failing on paraphrases ("não precisa se
// preocupar", "não faça nada", "não se assuste") — every one a real e-mail could plausibly use.
// Inverting to a bounded lookahead against a small set of relevant VERB STEMS generalizes past
// exact wording: "não" only blocks the match if, within a few words, it is followed by one of
// these reassurance/irrelevant verbs — "não identificamos pendências" (an unrelated finding,
// not a negation of the "quitada" that follows after a colon) is included here as its own idiom
// for the same reason.
const REASSURANCE_VERB_RE =
  '(?:se\\s+)?preocup\\w*|assust\\w*|fa[çc]a\\s+nada|precisa\\w*|h[áa]\\s+necessidade|[ée]\\s+preciso|identificamos\\s+pend[êe]ncias';
const NEGATION_RE = new RegExp(
  `\\b(n[ãa]o|nunca|jamais)\\b(?!(?:\\s+\\w+){0,3}?\\s*(?:${REASSURANCE_VERB_RE}))`,
  'i',
);
// A negation is looked for anywhere in the same CLAUSE as the match, not a fixed character
// count back — a fixed window (previously 20 chars) misses negation in a longer, entirely
// realistic sentence ("Informamos que sua fatura do cartão não foi identificada como quitada"
// has 30+ chars between "não" and "quitada"). Clauses split only on sentence terminators (.!?)
// and newlines — NOT commas, colons or dashes: a comma-set-off aside ("não foi, até o momento,
// quitada") is still one continuous clause and must not let the negation "fall out of scope" on
// the far side of a comma, and a colon-introduced continuation ("Não identificamos pendências:
// sua fatura está quitada") is handled by the reassurance-verb exclusion above instead of by
// splitting — splitting on colon was tried and broke the opposite, equally real case ("Não
// conseguimos localizar o seguinte: recibo de pagamento da sua fatura", which must stay
// unsettled — the colon there does NOT introduce an unrelated clause).
const CLAUSE_SPLIT_RE = /[.!?]+|\n+/;

/** MIME headers occasionally arrive Unicode-NFD (accents as combining marks), which would
 *  silently defeat the precomposed `ã`/`õ` in the patterns above. Also tolerates `undefined`/
 *  `null` defensively, even though every current caller already normalizes missing text to `''`
 *  before this point (Gmail metadata headers, e-mail body extraction). */
function normalize(text: string | null | undefined): string {
  return (text ?? '').normalize('NFC');
}

export function isCardInvoiceSubject(assunto: string): boolean {
  const normalized = normalize(assunto);
  return CARD_INVOICE_SUBJECT_PATTERNS.some((pattern) =>
    pattern.test(normalized),
  );
}

const UB =
  '(?:(?<![\\p{L}\\p{N}])(?=[\\p{L}\\p{N}])|(?<=[\\p{L}\\p{N}])(?![\\p{L}\\p{N}]))';
/** Verbo/estado de ciclo de cobrança ATIVO (fechou/chegou/disponível/vence/em aberto/ainda não
 *  paga...). Só formas VERBAIS: o substantivo "vencimento" fica de fora, porque "Comprovante de
 *  pagamento: R$ 120,00 - vencimento 05/10" é recibo, não cobrança. Mesmos radicais do S1a/S2 do
 *  detector — precisa acompanhar quando eles mudarem. */
const ACTIVE_BILLING_RE = new RegExp(
  `${UB}(?:fechou|fechada|chegou|dispon[ií]ve(?:l|is)|gerad[oa]s?|emitid[oa]s?|em atraso|pendente|em aberto|at[ée] (?:o )?dia \\d|venc(?:e|em|eu|endo|er[áa]|id[oa]s?)|(?:ainda )?n[ãa]o (?:foi |est[áa] |estava )?paga)${UB}`,
  'iu',
);
/** A oração ativa precisa nomear o documento ou o próximo ciclo: "veja o extrato disponível" tem
 *  verbo de ciclo mas é o EXTRATO que está disponível — a fatura foi paga. */
const BILLING_SUBJECT_RE = new RegExp(
  `${UB}(?:faturas?|boletos?|carnês?|cobran[çc]as?|mensalidades?|parcelas?|pr[óo]ximas?|novas?|atual|atuais)${UB}`,
  'iu',
);
/** Separadores de oração para a checagem de cobrança vigente: além de . ! ? ; : , e travessão,
 *  hífen/barra cercados de espaço e parênteses/colchetes ("Fatura paga - a próxima vence dia 10",
 *  "Fatura paga (a próxima já está disponível)"). */
const ACTIVE_CLAUSE_SPLIT_RE = /[.!?;:,—–()[\]]+|\s[-/]\s|\n+/;

export function hasActiveBillingClause(text: string): boolean {
  return normalize(text)
    .split(ACTIVE_CLAUSE_SPLIT_RE)
    .some(
      (clause) =>
        !isSettledPaymentSubject(clause) &&
        ACTIVE_BILLING_RE.test(clause) &&
        BILLING_SUBJECT_RE.test(clause),
    );
}

/** "Fatura anterior paga. Fatura de outubro disponível": a 1ª oração é liquidação, a 2ª anuncia a
 *  cobrança vigente. O veto de "pagamento já feito" só vale quando NENHUMA outra oração traz
 *  cobrança vigente. É a checagem que a triagem, a evidência negativa do parser (assunto e corpo) e
 *  o classificador heurístico usam — se uma delas olhasse o texto inteiro, as outras seriam letra
 *  morta. */
export function isSettledWithoutActiveBilling(text: string): boolean {
  return isSettledPaymentSubject(text) && !hasActiveBillingClause(text);
}

export function isSettledPaymentSubject(text: string): boolean {
  const normalized = normalize(text);
  const clauses = normalized.split(CLAUSE_SPLIT_RE);
  return SETTLED_PAYMENT_SUBJECT_PATTERNS.some((pattern) =>
    clauses.some((clause) => {
      const match = clause.match(pattern);
      if (!match || match.index === undefined) return false;
      // Negation can sit either right before the match ("não foi paga") or inside the matched
      // gap itself ("pagamento não confirmado", where the gap absorbs "não" between the two
      // anchor words) — checked across the whole clause up to the match end, not just a fixed
      // lookback, so it isn't missed in a longer sentence.
      return !NEGATION_RE.test(clause.slice(0, match.index + match[0].length));
    }),
  );
}
