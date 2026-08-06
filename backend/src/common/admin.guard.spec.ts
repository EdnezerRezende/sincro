import { ForbiddenException } from '@nestjs/common';
import { AdminGuard } from './admin.guard';

function buildContext(firebaseUid: string) {
  return {
    switchToHttp: () => ({ getRequest: () => ({ firebaseUid }) }),
  } as any;
}

describe('AdminGuard', () => {
  it('allows access for an admin user', async () => {
    const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1', isAdmin: true }) };
    const guard = new AdminGuard(usersService as any);

    await expect(guard.canActivate(buildContext('fb1'))).resolves.toBe(true);
  });

  it('rejects a non-admin user', async () => {
    const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1', isAdmin: false }) };
    const guard = new AdminGuard(usersService as any);

    await expect(guard.canActivate(buildContext('fb1'))).rejects.toThrow(ForbiddenException);
  });
});
