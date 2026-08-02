import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sincro_mobile/core/api_client.dart';

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUser extends Mock implements User {}

void main() {
  test('attaches the Firebase ID token as a bearer header when a user is signed in',
      () async {
    final mockAuth = MockFirebaseAuth();
    final mockUser = MockUser();
    when(() => mockUser.getIdToken()).thenAnswer((_) async => 'fake-id-token');
    when(() => mockAuth.currentUser).thenReturn(mockUser);

    final apiClient =
        ApiClient(baseUrl: 'http://localhost:3000', firebaseAuth: mockAuth);
    final options = RequestOptions(path: '/users/me');
    final handler = RequestInterceptorHandler();

    // Find our custom Firebase token interceptor
    final firebaseInterceptor = apiClient.dio.interceptors
        .whereType<FirebaseTokenInterceptor>()
        .first;
    await firebaseInterceptor.onRequest(options, handler);

    expect(options.headers['Authorization'], 'Bearer fake-id-token');
  });

  test('does not attach an Authorization header when no user is signed in',
      () async {
    final mockAuth = MockFirebaseAuth();
    when(() => mockAuth.currentUser).thenReturn(null);

    final apiClient =
        ApiClient(baseUrl: 'http://localhost:3000', firebaseAuth: mockAuth);
    final options = RequestOptions(path: '/users/me');
    final handler = RequestInterceptorHandler();

    final firebaseInterceptor = apiClient.dio.interceptors
        .whereType<FirebaseTokenInterceptor>()
        .first;
    await firebaseInterceptor.onRequest(options, handler);

    expect(options.headers.containsKey('Authorization'), isFalse);
  });
}

