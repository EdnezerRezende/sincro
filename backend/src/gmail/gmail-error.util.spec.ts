import { GaxiosError } from 'googleapis-common/node_modules/gaxios';
import { classificarErroGmail } from './gmail-error.util';

function gaxios(status?: number, extra: Record<string, unknown> = {}) {
  const err = new GaxiosError('x', { url: 'https://gmail' } as any, status ? ({ status, data: {} } as any) : undefined);
  if (status) (err as any).code = status;
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
  ])('%p → %s', (err, esperado) => {
    expect(classificarErroGmail(err)).toBe(esperado);
  });
});
