import { InternalServerErrorException } from '@nestjs/common';
import { GaxiosError } from 'googleapis-common/node_modules/gaxios';
import { classificarErroGmail } from './gmail-error.util';

function gaxios(status?: number, extra: Record<string, unknown> = {}) {
  const err = new GaxiosError(
    'x',
    { url: 'https://gmail' } as any,
    status ? ({ status, data: {} } as any) : undefined,
  );
  if (status) (err as any).code = status;
  Object.assign(err, extra);
  return err;
}

/** Forma REAL de um refresh token revogado/expirado: o gaxios derruba a troca de token no endpoint
 *  `/token` do Google — um GaxiosError HTTP 400 com `message === 'invalid_grant'` e
 *  `response.data.error === 'invalid_grant'`, não um erro na própria chamada à API do Gmail. */
function invalidGrant() {
  return new GaxiosError(
    'invalid_grant',
    { url: 'https://oauth2.googleapis.com/token' } as any,
    {
      status: 400,
      data: {
        error: 'invalid_grant',
        error_description: 'Token has been expired or revoked.',
      },
    } as any,
  );
}

/** Forma REAL de um erro de rede/timeout do node-fetch por baixo do gaxios 7: `code` no topo pode vir
 *  `undefined`, com o código/nome real em `error` (campo legado) e em `cause`. */
function gaxiosFetchError(extra: Record<string, unknown>) {
  const err = new GaxiosError('x', { url: 'https://gmail' } as any, undefined);
  Object.assign(err, extra);
  return err;
}

describe('classificarErroGmail', () => {
  it.each([
    [gaxios(429), 'transitorio-conta'],
    [gaxios(401), 'transitorio-conta'],
    [gaxios(403), 'transitorio-conta'],
    [gaxios(503), 'transitorio-mensagem'],
    [gaxios(500), 'transitorio-mensagem'],
    [gaxios(404), 'permanente'],
    [gaxios(400), 'permanente'],
    [gaxios(undefined, { code: 'ENOTFOUND' }), 'transitorio-conta'],
    [gaxios(undefined, { code: 'ECONNRESET' }), 'transitorio-conta'],
    [gaxios(undefined, { error: { name: 'AbortError' } }), 'transitorio-conta'],
    [gaxios(undefined, { cause: { code: 'ETIMEDOUT' } }), 'transitorio-conta'],
    [gaxios(undefined), 'transitorio-conta'],
    [new TypeError('bug'), 'permanente'],
    [{ code: 'P2002' }, 'permanente'],
    [invalidGrant(), 'transitorio-conta'],
    [new InternalServerErrorException('bug'), 'permanente'],
    [
      Object.assign(new Error('x'), { response: { status: 503 } }),
      'permanente',
    ],
    [
      gaxiosFetchError({
        code: 'ENOTFOUND',
        error: { name: 'FetchError' },
        cause: { code: 'ENOTFOUND' },
      }),
      'transitorio-conta',
    ],
    [
      gaxiosFetchError({
        code: undefined,
        error: { name: 'AbortError' },
        cause: { name: 'AbortError' },
      }),
      'transitorio-conta',
    ],
  ])('%p → %s', (err, esperado) => {
    expect(classificarErroGmail(err)).toBe(esperado);
  });
});
