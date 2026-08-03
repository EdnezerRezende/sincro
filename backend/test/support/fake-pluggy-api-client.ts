import { PluggyApiClient, PluggyAccount, PluggyBoleto, PluggyItem } from '../../src/pluggy/pluggy-api-client.service';

// Fixture dates are relative to `Date.now()` (tomorrow, +2 days) so they reliably land inside a
// "no dia_recebimento set" cycle (today through the end of the current month) in the finance-flow
// e2e test. This has one known, low-probability flaky edge: if the suite runs on the last day of
// a month, "+1/+2 days" rolls into next month and falls outside that cycle. Not worth freezing the
// clock over; if it ever flakes, the fix is to set the test user's dia_recebimento explicitly via
// PATCH /users/me/dia-recebimento (Task 7) instead of relying on the default end-of-month cycle.
export function buildFakePluggyApiClient(): Partial<PluggyApiClient> {
  const accountsByItem: Record<string, PluggyAccount[]> = {
    'item-tenant-1': [
      { id: 'acc-corrente-1', type: 'BANK', name: 'Conta Corrente', balance: 2000 },
      {
        id: 'acc-cartao-1',
        type: 'CREDIT',
        name: 'Cartão Principal',
        balance: 500,
        creditData: { balanceCloseDate: new Date(Date.now() + 2 * 86400000).toISOString().slice(0, 10) },
      },
    ],
    'item-tenant-2': [{ id: 'acc-corrente-2', type: 'BANK', name: 'Conta Corrente', balance: 800 }],
  };
  const boletosByItem: Record<string, PluggyBoleto[]> = {
    'item-tenant-1': [
      {
        codigoBarras: '111.222.333',
        valor: 100,
        vencimento: new Date(Date.now() + 1 * 86400000).toISOString().slice(0, 10),
      },
    ],
    'item-tenant-2': [],
  };

  return {
    createConnectToken: async () => 'fake-connect-token',
    getItem: async (itemId: string): Promise<PluggyItem> => ({
      id: itemId,
      connector: { name: 'Banco Fake' },
      status: 'UPDATED',
    }),
    listAccounts: async (itemId: string) => accountsByItem[itemId] ?? [],
    listBoletos: async (itemId: string) => boletosByItem[itemId] ?? [],
    deleteItem: async () => undefined,
  };
}
