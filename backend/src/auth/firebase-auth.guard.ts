import { CanActivate, ExecutionContext, Inject, Injectable, UnauthorizedException } from '@nestjs/common';
import { FIREBASE_ADMIN } from './firebase-admin.provider';
import type { FirebaseAdmin } from './firebase-admin.provider';

@Injectable()
export class FirebaseAuthGuard implements CanActivate {
  constructor(@Inject(FIREBASE_ADMIN) private readonly firebaseAdmin: FirebaseAdmin) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const authHeader: string | undefined = request.headers['authorization'];

    if (!authHeader?.startsWith('Bearer ')) {
      throw new UnauthorizedException('Missing bearer token');
    }

    const idToken = authHeader.substring('Bearer '.length);

    try {
      const decoded = await this.firebaseAdmin.auth().verifyIdToken(idToken);
      request.firebaseUid = decoded.uid;
      return true;
    } catch {
      throw new UnauthorizedException('Invalid token');
    }
  }
}
