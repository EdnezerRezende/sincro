import { Injectable } from '@nestjs/common';
import { google } from 'googleapis';

@Injectable()
export class GmailOAuthService {
  private buildClient() {
    return new google.auth.OAuth2(process.env.GOOGLE_CLIENT_ID, process.env.GOOGLE_CLIENT_SECRET);
  }

  async exchangeServerAuthCode(serverAuthCode: string): Promise<{ refreshToken: string }> {
    const client = this.buildClient();
    const { tokens } = await client.getToken(serverAuthCode);
    if (!tokens.refresh_token) {
      throw new Error(
        'O Google não retornou um refresh token. Isso geralmente acontece quando o acesso já ' +
          'foi concedido antes — revogue o acesso em https://myaccount.google.com/permissions ' +
          'e tente conectar novamente.',
      );
    }
    return { refreshToken: tokens.refresh_token };
  }

  authenticatedClientFor(refreshToken: string) {
    const client = this.buildClient();
    client.setCredentials({ refresh_token: refreshToken });
    return client;
  }

  async getEmailAddress(refreshToken: string): Promise<string> {
    const auth = this.authenticatedClientFor(refreshToken);
    const { data } = await google.oauth2('v2').userinfo.get({ auth });
    return data.email ?? '';
  }

  async revoke(refreshToken: string): Promise<void> {
    const client = this.authenticatedClientFor(refreshToken);
    await client.revokeToken(refreshToken);
  }
}
