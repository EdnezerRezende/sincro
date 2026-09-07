import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'auth_service.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

final googleSignInProvider = Provider<GoogleSignIn>((ref) => GoogleSignIn());

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(
    ref.watch(firebaseAuthProvider),
    // Lazy: só constrói o GoogleSignIn (e dispara a inicialização do plugin
    // web) quando o fluxo de login/logout com Google for realmente usado.
    // Se fosse `ref.watch(googleSignInProvider)` aqui, o simples fato de ler
    // `authServiceProvider` (inclusive para login por e-mail/senha) já
    // construiria o GoogleSignIn e dispararia `initWithParams` no plugin web
    // — que lança `Null check operator used on a null value` de forma não
    // tratada quando não há client ID do Google configurado (ver
    // google_sign_in_web `initWithParams`, linha `clientId: appClientId!`).
    () => ref.read(googleSignInProvider),
  );
});

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges();
});
