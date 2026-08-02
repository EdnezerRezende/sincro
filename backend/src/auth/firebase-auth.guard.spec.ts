import { ExecutionContext, UnauthorizedException } from '@nestjs/common';
import { FirebaseAuthGuard } from './firebase-auth.guard';
import { FIREBASE_ADMIN } from './firebase-admin.provider';

function buildContext(headers: Record<string, string>): ExecutionContext {
  const request: any = { headers };
  return {
    switchToHttp: () => ({ getRequest: () => request }),
  } as ExecutionContext;
}

describe('FirebaseAuthGuard', () => {
  it('throws UnauthorizedException when there is no bearer token', async () => {
    const fakeAdmin: any = { auth: () => ({ verifyIdToken: jest.fn() }) };
    const guard = new FirebaseAuthGuard(fakeAdmin);
    const context = buildContext({});

    await expect(guard.canActivate(context)).rejects.toThrow(UnauthorizedException);
  });

  it('sets request.firebaseUid and returns true for a valid token', async () => {
    const verifyIdToken = jest.fn().mockResolvedValue({ uid: 'user-123' });
    const fakeAdmin: any = { auth: () => ({ verifyIdToken }) };
    const guard = new FirebaseAuthGuard(fakeAdmin);
    const context = buildContext({ authorization: 'Bearer valid-token' });

    const result = await guard.canActivate(context);

    expect(result).toBe(true);
    expect(context.switchToHttp().getRequest().firebaseUid).toBe('user-123');
    expect(verifyIdToken).toHaveBeenCalledWith('valid-token');
  });

  it('throws UnauthorizedException when the token is invalid', async () => {
    const verifyIdToken = jest.fn().mockRejectedValue(new Error('bad token'));
    const fakeAdmin: any = { auth: () => ({ verifyIdToken }) };
    const guard = new FirebaseAuthGuard(fakeAdmin);
    const context = buildContext({ authorization: 'Bearer bad-token' });

    await expect(guard.canActivate(context)).rejects.toThrow(UnauthorizedException);
  });
});
