const FULL_SCOPE =
  'https://www.googleapis.com/auth/gmail.readonly ' +
  'https://www.googleapis.com/auth/gmail.send ' +
  'https://www.googleapis.com/auth/calendar.events';

export function buildFakeGmailOAuth(options: { scope?: string } = {}) {
  return {
    exchangeServerAuthCode: async (code: string) => ({
      refreshToken: `fake-refresh-token-for-${code}`,
      scope: options.scope ?? FULL_SCOPE,
    }),
    authenticatedClientFor: () => ({}),
    getEmailAddress: async () => 'usuario.teste@gmail.com',
    revoke: async () => undefined,
  };
}
