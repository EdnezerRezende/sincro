import { Module } from '@nestjs/common';
import { firebaseAdminProvider } from './firebase-admin.provider';
import { FirebaseAuthGuard } from './firebase-auth.guard';

@Module({
  providers: [firebaseAdminProvider, FirebaseAuthGuard],
  exports: [firebaseAdminProvider, FirebaseAuthGuard],
})
export class AuthModule {}
