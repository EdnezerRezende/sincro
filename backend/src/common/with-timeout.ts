/** Erro lançado quando `withTimeout` estoura o prazo — usado por
 *  `GmailApiClient.fetchPdfAttachmentText` (Task 10) para distinguir "PDF grande/travado" de erro
 *  real do `pdf-parse`, e tratar os dois como "PDF ilegível" (`valor` fica `null`). */
export class TimeoutError extends Error {
  constructor(ms: number) {
    super(`Tempo esgotado após ${ms} ms`);
    this.name = 'TimeoutError';
  }
}

/** `Promise.race` entre `p` e um timer: se `p` não resolver/rejeitar dentro de `ms`, rejeita com
 *  `TimeoutError`. O timer é sempre limpo (`finally` em `p`), evitando handle pendente no event
 *  loop quando `p` vence a corrida. */
export function withTimeout<T>(p: Promise<T>, ms: number): Promise<T> {
  let t: NodeJS.Timeout;
  return Promise.race([
    p.finally(() => clearTimeout(t)),
    new Promise<never>((_, reject) => {
      t = setTimeout(() => reject(new TimeoutError(ms)), ms);
    }),
  ]);
}
