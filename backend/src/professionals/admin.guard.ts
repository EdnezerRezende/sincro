import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { UsersService } from '../users/users.service';

@Injectable()
export class AdminGuard implements CanActivate {
  constructor(private readonly usersService: UsersService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const user = await this.usersService.getByFirebaseUidOrThrow(request.firebaseUid);
    if (!user.isAdmin) {
      throw new ForbiddenException('Acesso restrito a administradores');
    }
    return true;
  }
}
