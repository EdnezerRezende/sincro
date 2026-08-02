import { TokenCryptoService } from './token-crypto.service';
import { randomBytes } from 'crypto';

describe('TokenCryptoService', () => {
  const originalEnv = process.env.TOKEN_ENCRYPTION_KEY;

  beforeEach(() => {
    process.env.TOKEN_ENCRYPTION_KEY = randomBytes(32).toString('base64');
  });

  afterEach(() => {
    process.env.TOKEN_ENCRYPTION_KEY = originalEnv;
  });

  it('round-trips a plaintext string through encrypt and decrypt', () => {
    const service = new TokenCryptoService();
    const ciphertext = service.encrypt('meu-refresh-token-secreto');

    expect(ciphertext).not.toBe('meu-refresh-token-secreto');
    expect(service.decrypt(ciphertext)).toBe('meu-refresh-token-secreto');
  });

  it('produces different ciphertext for the same plaintext on repeated calls', () => {
    const service = new TokenCryptoService();
    const a = service.encrypt('mesmo-valor');
    const b = service.encrypt('mesmo-valor');

    expect(a).not.toBe(b);
  });

  it('throws when the ciphertext has been tampered with', () => {
    const service = new TokenCryptoService();
    const ciphertext = service.encrypt('valor-original');
    const tampered = ciphertext.slice(0, -4) + 'AAAA';

    expect(() => service.decrypt(tampered)).toThrow();
  });

  it('throws at construction time when TOKEN_ENCRYPTION_KEY is missing', () => {
    delete process.env.TOKEN_ENCRYPTION_KEY;

    expect(() => new TokenCryptoService()).toThrow('TOKEN_ENCRYPTION_KEY');
  });
});
