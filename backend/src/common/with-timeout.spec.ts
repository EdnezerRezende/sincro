import { TimeoutError, withTimeout } from './with-timeout';

describe('withTimeout', () => {
  it('resolves when fast', async () => {
    await expect(withTimeout(Promise.resolve(1), 50)).resolves.toBe(1);
  });

  it('rejects with TimeoutError when slow', async () => {
    await expect(withTimeout(new Promise((r) => setTimeout(r, 200)), 20)).rejects.toBeInstanceOf(
      TimeoutError,
    );
  });
});
