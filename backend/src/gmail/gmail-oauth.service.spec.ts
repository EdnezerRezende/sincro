import { UnprocessableEntityException } from '@nestjs/common';
import { GmailOAuthService } from './gmail-oauth.service';

jest.mock('googleapis', () => {
  const mockOAuth2Client = {
    getToken: jest.fn(),
    setCredentials: jest.fn(),
    revokeToken: jest.fn(),
  };
  return {
    google: {
      auth: { OAuth2: jest.fn(() => mockOAuth2Client) },
      oauth2: jest.fn(() => ({ userinfo: { get: jest.fn() } })),
    },
    __mockOAuth2Client: mockOAuth2Client,
  };
});

describe('GmailOAuthService', () => {
  beforeEach(() => {
    process.env.GOOGLE_CLIENT_ID = 'test-client-id';
    process.env.GOOGLE_CLIENT_SECRET = 'test-client-secret';
  });

  it('exchanges a serverAuthCode for a refresh token', async () => {
    const { google } = jest.requireMock('googleapis');
    const mockClient = google.auth.OAuth2();
    mockClient.getToken.mockResolvedValue({
      tokens: { refresh_token: 'rt-123', access_token: 'at-123', scope: 'https://www.googleapis.com/auth/gmail.readonly' },
    });

    const service = new GmailOAuthService();
    const result = await service.exchangeServerAuthCode('code-abc');

    expect(result).toEqual({ refreshToken: 'rt-123', scope: 'https://www.googleapis.com/auth/gmail.readonly' });
    expect(mockClient.getToken).toHaveBeenCalledWith('code-abc');
  });

  it('throws a clear error when Google does not return a refresh token', async () => {
    const { google } = jest.requireMock('googleapis');
    const mockClient = google.auth.OAuth2();
    mockClient.getToken.mockResolvedValue({ tokens: { access_token: 'at-123' } });

    const service = new GmailOAuthService();

    await expect(service.exchangeServerAuthCode('code-abc')).rejects.toThrow(/refresh token/i);
  });

  it('maps the missing-refresh-token case to an UnprocessableEntityException so the guidance message reaches the client', async () => {
    const { google } = jest.requireMock('googleapis');
    const mockClient = google.auth.OAuth2();
    mockClient.getToken.mockResolvedValue({ tokens: { access_token: 'at-123' } });

    const service = new GmailOAuthService();

    await expect(service.exchangeServerAuthCode('code-abc')).rejects.toThrow(UnprocessableEntityException);
    await expect(service.exchangeServerAuthCode('code-abc')).rejects.toThrow(
      /revogue o acesso em https:\/\/myaccount\.google\.com\/permissions/,
    );
  });
});
