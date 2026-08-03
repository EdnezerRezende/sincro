import { PluggyApiClient } from './pluggy-api-client.service';

function jsonResponse(body: unknown, status = 200): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  } as Response;
}

describe('PluggyApiClient', () => {
  const originalFetch = global.fetch;
  const originalEnv = { ...process.env };

  beforeEach(() => {
    process.env.PLUGGY_CLIENT_ID = 'client-id';
    process.env.PLUGGY_CLIENT_SECRET = 'client-secret';
  });

  afterEach(() => {
    global.fetch = originalFetch;
    process.env = { ...originalEnv };
  });

  it('authenticates once and reuses the cached apiKey across calls', async () => {
    const fetchMock = jest
      .fn()
      .mockResolvedValueOnce(jsonResponse({ apiKey: 'key-1' }))
      .mockResolvedValueOnce(jsonResponse({ results: [] }))
      .mockResolvedValueOnce(jsonResponse({ results: [] }));
    global.fetch = fetchMock as unknown as typeof fetch;

    const client = new PluggyApiClient();
    await client.listAccounts('item-1');
    await client.listAccounts('item-1');

    const authCalls = fetchMock.mock.calls.filter((call) => (call[0] as string).endsWith('/auth'));
    expect(authCalls).toHaveLength(1);
  });

  it('lists accounts mapped from the Pluggy response', async () => {
    const fetchMock = jest
      .fn()
      .mockResolvedValueOnce(jsonResponse({ apiKey: 'key-1' }))
      .mockResolvedValueOnce(
        jsonResponse({ results: [{ id: 'acc-1', type: 'BANK', name: 'Conta Corrente', balance: 1500 }] }),
      );
    global.fetch = fetchMock as unknown as typeof fetch;

    const client = new PluggyApiClient();
    const accounts = await client.listAccounts('item-1');

    expect(accounts).toEqual([{ id: 'acc-1', type: 'BANK', name: 'Conta Corrente', balance: 1500 }]);
  });

  it('refreshes the apiKey and retries once when a request returns 403', async () => {
    const fetchMock = jest
      .fn()
      .mockResolvedValueOnce(jsonResponse({ apiKey: 'key-1' }))
      .mockResolvedValueOnce(jsonResponse({}, 403))
      .mockResolvedValueOnce(jsonResponse({ apiKey: 'key-2' }))
      .mockResolvedValueOnce(jsonResponse({ results: [] }));
    global.fetch = fetchMock as unknown as typeof fetch;

    const client = new PluggyApiClient();
    await expect(client.listAccounts('item-1')).resolves.toEqual([]);

    const authCalls = fetchMock.mock.calls.filter((call) => (call[0] as string).endsWith('/auth'));
    expect(authCalls).toHaveLength(2);
  });

  it('handles a 204 No Content response without trying to parse an empty body', async () => {
    // DELETE /items/{id} responde 204 sem corpo; chamar response.json() aí lança e faz o
    // disconnect logar "Failed to delete Pluggy item" mesmo tendo dado certo.
    const noContent = {
      ok: true,
      status: 204,
      json: async () => {
        throw new SyntaxError('Unexpected end of JSON input');
      },
    } as unknown as Response;
    const fetchMock = jest.fn().mockResolvedValueOnce(jsonResponse({ apiKey: 'key-1' })).mockResolvedValueOnce(noContent);
    global.fetch = fetchMock as unknown as typeof fetch;

    const client = new PluggyApiClient();

    await expect(client.deleteItem('item-1')).resolves.toBeUndefined();
  });

  it('throws when PLUGGY_CLIENT_ID/PLUGGY_CLIENT_SECRET are not configured', async () => {
    delete process.env.PLUGGY_CLIENT_ID;
    const client = new PluggyApiClient();

    await expect(client.listAccounts('item-1')).rejects.toThrow(
      'PLUGGY_CLIENT_ID/PLUGGY_CLIENT_SECRET não configurados.',
    );
  });
});
