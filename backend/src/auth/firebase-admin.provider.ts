import { Provider } from '@nestjs/common';
import { cert, getApps, initializeApp } from 'firebase-admin/app';
import type { App } from 'firebase-admin/app';
import type { Auth } from 'firebase-admin/auth';
import { getMessaging } from 'firebase-admin/messaging';
import type { Messaging } from 'firebase-admin/messaging';

export const FIREBASE_ADMIN = 'FIREBASE_ADMIN';

export interface FirebaseAdmin {
  auth(): Auth;
  messaging(): Messaging;
}

// `firebase-admin/auth` transitively requires `jwks-rsa` -> `jose`, and `jose` v6 ships
// ESM-only with no CommonJS export condition. Real Node (v22+) transparently interops via
// require(esm), but Jest's own module loader does not, so a static top-level import of
// `firebase-admin/auth` breaks every spec file that merely imports this module for the
// FIREBASE_ADMIN token (even when the token itself is overridden with a fake in tests).
// Deferring the require to first call keeps it off the module-load path entirely.
/* eslint-disable @typescript-eslint/no-require-imports, @typescript-eslint/no-unsafe-assignment */
function lazyGetAuth(app: App): Auth {
  const mod: typeof import('firebase-admin/auth') = require('firebase-admin/auth');
  return mod.getAuth(app);
}
/* eslint-enable @typescript-eslint/no-require-imports, @typescript-eslint/no-unsafe-assignment */

export const firebaseAdminProvider: Provider = {
  provide: FIREBASE_ADMIN,
  useFactory: (): FirebaseAdmin => {
    const existingApps = getApps();
    const app: App =
      existingApps.length === 0
        ? initializeApp({
            credential: cert({
              projectId: process.env.FIREBASE_PROJECT_ID,
              clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
              privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(
                /\\n/g,
                '\n',
              ),
            }),
          })
        : existingApps[0];

    return {
      auth: () => lazyGetAuth(app),
      messaging: () => getMessaging(app),
    };
  },
};
