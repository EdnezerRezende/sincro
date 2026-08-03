import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sincro_mobile/features/email_triage/gmail_connection_repository.dart';

class MockGoogleSignIn extends Mock implements GoogleSignIn {}

class MockGoogleSignInAccount extends Mock implements GoogleSignInAccount {}

void main() {
  test('connect signs in with Google and posts the serverAuthCode', () async {
    final mockGoogleSignIn = MockGoogleSignIn();
    final mockAccount = MockGoogleSignInAccount();
    when(() => mockAccount.serverAuthCode).thenReturn('auth-code-123');
    when(() => mockGoogleSignIn.signIn()).thenAnswer((_) async => mockAccount);

    String? capturedPath;
    Object? capturedData;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedPath = options.path;
      capturedData = options.data;
      handler.resolve(Response(requestOptions: options, statusCode: 201, data: {'success': true}));
    }));

    final repository = GmailConnectionRepository(dio, mockGoogleSignIn);
    await repository.connect();

    expect(capturedPath, '/gmail/connect');
    expect(capturedData, {'serverAuthCode': 'auth-code-123'});
  });

  test('connect throws when the user cancels the Google sign-in', () async {
    final mockGoogleSignIn = MockGoogleSignIn();
    when(() => mockGoogleSignIn.signIn()).thenAnswer((_) async => null);
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));

    final repository = GmailConnectionRepository(dio, mockGoogleSignIn);

    expect(() => repository.connect(), throwsException);
  });

  test('status parses the connection response', () async {
    final mockGoogleSignIn = MockGoogleSignIn();
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: {'connected': true, 'gmailEmail': 'ana@example.com'},
      ));
    }));

    final repository = GmailConnectionRepository(dio, mockGoogleSignIn);
    final status = await repository.status();

    expect(status.connected, true);
    expect(status.gmailEmail, 'ana@example.com');
  });

  test('disconnect calls the delete endpoint and signs out of Google', () async {
    final mockGoogleSignIn = MockGoogleSignIn();
    when(() => mockGoogleSignIn.signOut()).thenAnswer((_) async => null);
    String? capturedPath;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedPath = options.path;
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {'success': true}));
    }));

    final repository = GmailConnectionRepository(dio, mockGoogleSignIn);
    await repository.disconnect();

    expect(capturedPath, '/gmail/connection');
    verify(() => mockGoogleSignIn.signOut()).called(1);
  });
}
