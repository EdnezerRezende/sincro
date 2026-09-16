import {
  ForbiddenException,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';

/** Extracts the HTTP status Google's client attached to a failed API call. Different
 *  releases/paths through `googleapis`/`gaxios` have put this in different places
 *  (`error.response.status`, `error.status`, or a numeric `error.code`) — checking all three means
 *  a genuine 404/401/403 from Gmail is never mistaken for "some other failure" just because of
 *  where the library happened to attach it. */
export function statusHttpDoErroGmail(error: unknown): number | undefined {
  const err = error as
    | { status?: unknown; code?: unknown; response?: { status?: unknown } }
    | null
    | undefined;
  const candidatos = [err?.response?.status, err?.status, err?.code];
  for (const candidato of candidatos) {
    if (typeof candidato === 'number') return candidato;
  }
  return undefined;
}

/** True when the Gmail API rejected the call because the message itself no longer exists there
 *  (already deleted straight from Gmail, for example) — distinct from an auth failure, and the one
 *  case where the caller may want to treat the failure as "nothing to do" rather than an error. */
export function gmailMensagemNaoEncontrada(error: unknown): boolean {
  return statusHttpDoErroGmail(error) === 404;
}

/** Maps a failed Gmail API call to an honest, Portuguese HTTP response instead of letting it fall
 *  through as an unhandled 500 ("Internal server error" — the original symptom this endpoint set
 *  was built to fix). 401/403 mean the credential stopped working (refresh token revoked/expired,
 *  or the person withheld/removed that permission on Google's side) — the fix is always the same
 *  (reconnect), so both collapse into one 403, which is also the status the mobile client already
 *  knows how to react to for arquivar/excluir. A 404 means the message itself is gone from Gmail.
 *  Anything else (Gmail's own 5xx, a network hiccup) is a transient failure that isn't the user's
 *  fault, mapped to 503 so a retry is the obvious next step. */
export function mapearErroGmail(
  error: unknown,
  mensagemNaoEncontrado?: string,
): Error {
  const status = statusHttpDoErroGmail(error);
  if (status === 401 || status === 403) {
    return new ForbiddenException(
      'A conexão com o Gmail expirou ou perdeu essa permissão. Reconecte o Gmail e tente de novo.',
    );
  }
  if (status === 404) {
    return new NotFoundException(
      mensagemNaoEncontrado ?? 'Este e-mail não existe mais no Gmail.',
    );
  }
  return new ServiceUnavailableException(
    'Não foi possível falar com o Gmail agora. Tente novamente em instantes.',
  );
}

export type ClasseErroGmail =
  'transitorio-conta' | 'transitorio-mensagem' | 'permanente';

const CODES_REDE = new Set([
  'ECONNRESET',
  'ETIMEDOUT',
  'ECONNREFUSED',
  'EAI_AGAIN',
  'ENOTFOUND',
  'EPIPE',
]);
const NOMES_TIMEOUT = new Set(['AbortError', 'TimeoutError']);

/** Decide o que o reprocessamento faz com uma falha. Lê a forma REAL do gaxios 7: um timeout chega com
 *  `err.name === 'Error'` e `err.error.name === 'AbortError'`; erros de rede trazem `code` string; HTTP
 *  traz `status` numérico. Exceção que não veio do gaxios (parser, Prisma, `HttpException` do próprio
 *  Nest) é nossa → permanente — por isso `ehGaxios` NÃO usa `'response' in err` (toda `HttpException`
 *  tem `.response`) e sim `config`/o símbolo interno do gaxios/o nome do construtor. Um refresh token
 *  revogado/expirado não vira um HTTP na chamada à API do Gmail: ele derruba a troca de token ANTES
 *  disso, como um GaxiosError 400 do endpoint `/token` com `error: 'invalid_grant'` — sem essa checagem
 *  explícita cairia no fallthrough "outro 4xx → permanente" e carimbaria o lote inteiro como processado. */
export function classificarErroGmail(error: unknown): ClasseErroGmail {
  const err = (error ?? {}) as Record<string, any>;
  const ehGaxios =
    typeof err === 'object' &&
    err !== null &&
    ('config' in err ||
      Symbol.for('gaxios-gaxios-error') in err ||
      err?.constructor?.name === 'GaxiosError');
  if (!ehGaxios) return 'permanente';

  const status = statusHttpDoErroGmail(error);
  if (status === 401 || status === 403 || status === 429)
    return 'transitorio-conta';
  if (
    err.response?.data?.error === 'invalid_grant' ||
    err.message === 'invalid_grant' ||
    /\/token$/.test(String(err.config?.url ?? ''))
  ) {
    return 'transitorio-conta';
  }
  const codes = [err.code, err.error?.code, err.cause?.code].filter(
    (c) => typeof c === 'string',
  );
  const nomes = [err.name, err.error?.name, err.cause?.name].filter(
    (n) => typeof n === 'string',
  );
  if (
    codes.some((c) => CODES_REDE.has(c)) ||
    nomes.some((n) => NOMES_TIMEOUT.has(n))
  )
    return 'transitorio-conta';
  if (status === undefined) return 'transitorio-conta';
  if (status >= 500) return 'transitorio-mensagem';
  return 'permanente';
}
