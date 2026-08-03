export function buildFakeFirebaseAdmin() {
  return {
    auth: () => ({
      verifyIdToken: (token: string): Promise<{ uid: string }> => {
        if (!token.startsWith('test-uid:')) {
          return Promise.reject(new Error('invalid test token'));
        }
        return Promise.resolve({ uid: token.replace('test-uid:', '') });
      },
    }),
    messaging: () => ({
      send: async () => 'fake-message-id',
    }),
  };
}
