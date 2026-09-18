import { EmailSyncLockService } from './email-sync-lock.service';

describe('EmailSyncLockService', () => {
  it('executa a função e devolve o resultado', async () => {
    const lock = new EmailSyncLockService();
    await expect(lock.executar('u1', async () => 42)).resolves.toBe(42);
  });

  it('devolve null quando o mesmo usuário já está em execução', async () => {
    const lock = new EmailSyncLockService();
    let resolver!: () => void;
    const primeira = lock.executar(
      'u1',
      () =>
        new Promise<string>((r) => {
          resolver = () => r('ok');
        }),
    );
    await expect(lock.executar('u1', async () => 'segunda')).resolves.toBeNull();
    resolver();
    await expect(primeira).resolves.toBe('ok');
  });

  it('usuários diferentes correm em paralelo', async () => {
    const lock = new EmailSyncLockService();
    let resolver!: () => void;
    const lenta = lock.executar(
      'u1',
      () =>
        new Promise<string>((r) => {
          resolver = () => r('u1');
        }),
    );
    await expect(lock.executar('u2', async () => 'u2')).resolves.toBe('u2');
    resolver();
    await lenta;
  });

  it('libera o lock após erro', async () => {
    const lock = new EmailSyncLockService();
    await expect(
      lock.executar('u1', async () => {
        throw new Error('boom');
      }),
    ).rejects.toThrow('boom');
    await expect(lock.executar('u1', async () => 'de novo')).resolves.toBe('de novo');
  });
});
