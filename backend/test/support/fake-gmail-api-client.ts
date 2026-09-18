/** Mirrors the current `GmailApiClient` surface (see `src/gmail/gmail-api-client.service.ts`).
 *  `corpo` is a single shared body source reused by BOTH `fetchFullBody` (old contract, still used
 *  by `email-summary.controller.ts`/`email-reply.controller.ts`) and `fetchFullBodyComAnexos` (used
 *  by `FinanceEmailProcessor`) — a caller that needs a specific body (e.g. a finance e2e spec)
 *  passes `{ corpo }` instead of the two methods drifting out of sync.
 *
 *  `marcador` is configurable the same way, for specs exercising the `Sincro/Finanças` label path
 *  (`listarIdsComMarcador`) — defaults to "label doesn't exist yet" (`{ labelId: null, ids: new
 *  Set() }`), matching most accounts. */
export function buildFakeGmailApiClient(
  opts: {
    corpo?: string;
    marcador?: { labelId: string | null; ids: Set<string> };
  } = {},
) {
  const corpo = opts.corpo ?? 'Corpo completo de teste do e-mail original.';
  return {
    fetchInitial: async () => ({
      emails: [
        {
          gmailMessageId: 'msg-urgente',
          remetente: 'Banco Exemplo <contato@banco.example>',
          assunto: 'Fatura com vencimento urgente',
          corpo: 'Sua fatura vence em breve.',
          recebidoEm: new Date(),
          labelIds: ['INBOX'],
        },
        {
          gmailMessageId: 'msg-newsletter',
          remetente: 'Newsletter <news@example.com>',
          assunto: 'Novidades da semana',
          corpo: 'Confira as novidades.',
          recebidoEm: new Date(),
          labelIds: ['INBOX'],
        },
      ],
      historyId: 'history-1',
    }),
    fetchIncremental: async () => ({
      emails: [],
      historyId: 'history-1',
      historyExpired: false,
    }),
    fetchFullBody: async () => ({ texto: corpo, ehPreview: false }),
    fetchFullBodyComAnexos: async () => ({
      texto: corpo,
      ehPreview: false,
      anexos: [],
    }),
    fetchPdfAttachmentText: async () => null,
    arquivar: async () => undefined,
    excluir: async () => undefined,
    sendReply: async () => undefined,
    listarIdsComMarcador: async () =>
      opts.marcador ?? { labelId: null, ids: new Set<string>() },
  };
}
