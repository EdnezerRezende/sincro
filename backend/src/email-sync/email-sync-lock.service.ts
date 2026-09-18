import { Injectable } from '@nestjs/common';

/** Lock POR USUÁRIO, em memória (premissa: uma réplica). Substitui o guard global `running` do
 *  scheduler: um usuário lento (reprocessamento de finanças, PDF) não segura os outros, e o mesmo
 *  usuário nunca sincroniza em paralelo (cron × endpoint manual × evento de conexão). */
@Injectable()
export class EmailSyncLockService {
  private readonly emExecucao = new Set<string>();

  /** Executa `fn` se o usuário não estiver em sincronização; devolve `null` se pulou. */
  async executar<T>(userId: string, fn: () => Promise<T>): Promise<T | null> {
    if (this.emExecucao.has(userId)) return null;
    this.emExecucao.add(userId);
    try {
      return await fn();
    } finally {
      this.emExecucao.delete(userId);
    }
  }
}
