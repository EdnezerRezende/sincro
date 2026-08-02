import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/api_providers.dart';
import 'email_summary.dart';
import 'email_summary_repository.dart';
import 'gmail_connection_repository.dart';

const _gmailReadonlyScope = 'https://www.googleapis.com/auth/gmail.readonly';

const _googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

final googleSignInProvider = Provider<GoogleSignIn>((ref) {
  return GoogleSignIn(
    scopes: const [_gmailReadonlyScope],
    serverClientId: _googleWebClientId.isEmpty ? null : _googleWebClientId,
  );
});

final gmailConnectionRepositoryProvider = Provider<GmailConnectionRepository>((ref) {
  return GmailConnectionRepository(ref.watch(apiClientProvider).dio, ref.watch(googleSignInProvider));
});

final gmailConnectionStatusProvider = FutureProvider.autoDispose<GmailConnectionStatus>((ref) {
  return ref.watch(gmailConnectionRepositoryProvider).status();
});

final emailSummaryRepositoryProvider = Provider<EmailSummaryRepository>((ref) {
  return EmailSummaryRepository(ref.watch(apiClientProvider).dio);
});

final emailSummariesProvider = FutureProvider.autoDispose<List<EmailSummary>>((ref) {
  return ref.watch(emailSummaryRepositoryProvider).list();
});
