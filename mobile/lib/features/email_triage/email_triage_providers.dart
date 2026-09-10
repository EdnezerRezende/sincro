import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/api_providers.dart';
import 'email_summary.dart';
import 'email_summary_repository.dart';
import 'email_reply_repository.dart';
import 'fcm_token_repository.dart';
import 'gmail_connection_repository.dart';

const _gmailReadonlyScope = 'https://www.googleapis.com/auth/gmail.readonly';
const _gmailSendScope = 'https://www.googleapis.com/auth/gmail.send';
const _gmailModifyScope = 'https://www.googleapis.com/auth/gmail.modify';
const _calendarEventsScope = 'https://www.googleapis.com/auth/calendar.events';

const _googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

final googleSignInProvider = Provider<GoogleSignIn>((ref) {
  return GoogleSignIn(
    scopes: const [_gmailReadonlyScope, _gmailSendScope, _gmailModifyScope, _calendarEventsScope],
    serverClientId: _googleWebClientId.isEmpty ? null : _googleWebClientId,
    forceCodeForRefreshToken: true,
  );
});

final gmailConnectionRepositoryProvider = Provider<GmailConnectionRepository>((ref) {
  // `() => ref.read(googleSignInProvider)` em vez de `ref.watch(googleSignInProvider)`: watch
  // construiria o GoogleSignIn imediatamente sempre que este provider fosse lido — o que
  // acontece em toda tela que observa `gmailConnectionStatusProvider` (Home inclusive), mesmo
  // sem nenhuma intenção de iniciar sessão no Google. Ver o comentário em
  // `GmailConnectionRepository` para a exceção não tratada que isso causava no Flutter Web.
  return GmailConnectionRepository(ref.watch(apiClientProvider).dio, () => ref.read(googleSignInProvider));
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

final fcmTokenRepositoryProvider = Provider<FcmTokenRepository>((ref) {
  return FcmTokenRepository(ref.watch(apiClientProvider).dio);
});

final emailReplyRepositoryProvider = Provider<EmailReplyRepository>((ref) {
  return EmailReplyRepository(ref.watch(apiClientProvider).dio);
});
