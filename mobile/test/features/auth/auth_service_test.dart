import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sincro_mobile/features/auth/auth_service.dart';

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUserCredential extends Mock implements UserCredential {}

class MockUser extends Mock implements User {}

class MockGoogleSignIn extends Mock implements GoogleSignIn {}

void main() {
  late MockFirebaseAuth mockFirebaseAuth;
  late MockGoogleSignIn mockGoogleSignIn;
  late AuthService authService;

  setUp(() {
    mockFirebaseAuth = MockFirebaseAuth();
    mockGoogleSignIn = MockGoogleSignIn();
    authService = AuthService(mockFirebaseAuth, mockGoogleSignIn);
  });

  test('signUp delegates to createUserWithEmailAndPassword and returns the user', () async {
    final mockUser = MockUser();
    final mockCredential = MockUserCredential();
    when(() => mockCredential.user).thenReturn(mockUser);
    when(
      () => mockFirebaseAuth.createUserWithEmailAndPassword(
        email: 'ana@example.com',
        password: 'senha-forte-123',
      ),
    ).thenAnswer((_) async => mockCredential);

    final result = await authService.signUp('ana@example.com', 'senha-forte-123');

    expect(result, mockUser);
  });

  test('logIn delegates to signInWithEmailAndPassword and returns the user', () async {
    final mockUser = MockUser();
    final mockCredential = MockUserCredential();
    when(() => mockCredential.user).thenReturn(mockUser);
    when(
      () => mockFirebaseAuth.signInWithEmailAndPassword(
        email: 'ana@example.com',
        password: 'senha-forte-123',
      ),
    ).thenAnswer((_) async => mockCredential);

    final result = await authService.logIn('ana@example.com', 'senha-forte-123');

    expect(result, mockUser);
  });
}
