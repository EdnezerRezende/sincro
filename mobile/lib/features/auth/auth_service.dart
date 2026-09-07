import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService(this._firebaseAuth, this._googleSignInFactory);

  final FirebaseAuth _firebaseAuth;

  // Constrói o GoogleSignIn sob demanda: no web, `GoogleSignIn()` dispara a
  // inicialização do plugin (`initWithParams`) assim que é instanciado. Se
  // isso acontecesse aqui no construtor de AuthService, o login por
  // e-mail/senha (que também passa por este serviço) construiria o
  // GoogleSignIn sem necessidade, disparando essa inicialização — que lança
  // uma exceção não tratada quando não há client ID do Google configurado.
  // Adiando a construção para o primeiro uso real (signInWithGoogle/signOut),
  // o clique em "Entrar" deixa de acionar o plugin do Google inteiramente.
  final GoogleSignIn Function() _googleSignInFactory;
  GoogleSignIn? _googleSignIn;
  GoogleSignIn get _googleSignInInstance =>
      _googleSignIn ??= _googleSignInFactory();

  User? get currentUser => _firebaseAuth.currentUser;

  Stream<User?> authStateChanges() => _firebaseAuth.authStateChanges();

  Future<User?> signUp(String email, String password) async {
    final credential = await _firebaseAuth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    return credential.user;
  }

  Future<User?> logIn(String email, String password) async {
    final credential = await _firebaseAuth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return credential.user;
  }

  Future<User?> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignInInstance.signIn();
      if (googleUser == null) return null;

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _firebaseAuth.signInWithCredential(credential);
      return userCredential.user;
    } on FirebaseAuthException catch (_) {
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _firebaseAuth.signOut();
    await _googleSignInInstance.signOut();
  }
}
