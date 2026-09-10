import { ForbiddenException, NotFoundException, ServiceUnavailableException } from '@nestjs/common';

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
export function mapearErroGmail(error: unknown, mensagemNaoEncontrado?: string): Error {
  const status = statusHttpDoErroGmail(error);
  if (status === 401 || status === 403) {
    return new ForbiddenException(
      'A conexão com o Gmail expirou ou perdeu essa permissão. Reconecte o Gmail e tente de novo.',
    );
  }
  if (status === 404) {
    return new NotFoundException(mensagemNaoEncontrado ?? 'Este e-mail não existe mais no Gmail.');
  }
  return new ServiceUnavailableException('Não foi possível falar com o Gmail agora. Tente novamente em instantes.');
}
