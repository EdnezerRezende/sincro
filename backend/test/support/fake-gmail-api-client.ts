export function buildFakeGmailApiClient() {
  return {
    fetchInitialUnread: async () => ({
      emails: [
        {
          gmailMessageId: 'msg-urgente',
          remetente: 'Banco Exemplo <contato@banco.example>',
          assunto: 'Fatura com vencimento urgente',
          corpo: 'Sua fatura vence em breve.',
          recebidoEm: new Date(),
        },
        {
          gmailMessageId: 'msg-newsletter',
          remetente: 'Newsletter <news@example.com>',
          assunto: 'Novidades da semana',
          corpo: 'Confira as novidades.',
          recebidoEm: new Date(),
        },
      ],
      historyId: 'history-1',
    }),
    fetchIncremental: async () => ({ emails: [], historyId: 'history-1', historyExpired: false }),
  };
}
