import { Injectable } from '@nestjs/common';

const PLUGGY_BASE_URL = process.env.PLUGGY_BASE_URL ?? 'https://api.pluggy.ai';

export interface PluggyAccount {
  id: string;
  type: 'BANK' | 'CREDIT';
  name: string;
  balance: number;
  creditData?: { balanceCloseDate: string };
}

export interface PluggyBoleto {
  codigoBarras: string;
  valor: number;
  vencimento: string;
}

export interface PluggyItem {
  id: string;
  connector: { name: string };
  status: string;
}

@Injectable()
export class PluggyApiClient {
  private apiKey: string | null = null;

  async createConnectToken(): Promise<string> {
    const data = await this.request<{ accessToken: string }>('/connect_token', {
      method: 'POST',
      body: JSON.stringify({}),
    });
    return data.accessToken;
  }

  async getItem(itemId: string): Promise<PluggyItem> {
    return this.request<PluggyItem>(`/items/${itemId}`);
  }

  async listAccounts(itemId: string): Promise<PluggyAccount[]> {
    const data = await this.request<{ results: PluggyAccount[] }>(`/accounts?itemId=${itemId}`);
    return data.results;
  }

  async listBoletos(itemId: string): Promise<PluggyBoleto[]> {
    const data = await this.request<{ results: PluggyBoleto[] }>(`/bills?itemId=${itemId}`);
    return data.results;
  }

  async deleteItem(itemId: string): Promise<void> {
    await this.request(`/items/${itemId}`, { method: 'DELETE' });
  }

  private async authenticate(): Promise<string> {
    if (this.apiKey) return this.apiKey;
    const clientId = process.env.PLUGGY_CLIENT_ID;
    const clientSecret = process.env.PLUGGY_CLIENT_SECRET;
    if (!clientId || !clientSecret) {
      throw new Error('PLUGGY_CLIENT_ID/PLUGGY_CLIENT_SECRET não configurados.');
    }
    const response = await fetch(`${PLUGGY_BASE_URL}/auth`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ clientId, clientSecret }),
    });
    if (!response.ok) throw new Error(`Falha ao autenticar na Pluggy: ${response.status}`);
    const data = (await response.json()) as { apiKey: string };
    this.apiKey = data.apiKey;
    return this.apiKey;
  }

  // Retries exactly once on 403 (expired apiKey) with a freshly-authenticated key. Any other
  // non-OK status is a real failure and propagates immediately.
  private async request<T>(path: string, init?: RequestInit, isRetry = false): Promise<T> {
    const apiKey = await this.authenticate();
    const response = await fetch(`${PLUGGY_BASE_URL}${path}`, {
      ...init,
      headers: { ...(init?.headers ?? {}), 'X-API-KEY': apiKey, 'Content-Type': 'application/json' },
    });
    if (response.status === 403 && !isRetry) {
      this.apiKey = null;
      return this.request<T>(path, init, true);
    }
    if (!response.ok) throw new Error(`Pluggy request failed: ${path} (${response.status})`);
    return response.json() as Promise<T>;
  }
}
