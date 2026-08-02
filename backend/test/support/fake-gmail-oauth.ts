export function buildFakeGmailOAuth() {
  return {
    exchangeServerAuthCode: async (code: string) => ({ refreshToken: `fake-refresh-token-for-${code}` }),
    authenticatedClientFor: () => ({}),
    getEmailAddress: async () => 'usuario.teste@gmail.com',
    revoke: async () => undefined,
  };
}
