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

/// Estado da caixa de entrada: itens já carregados (de todas as páginas acumuladas até agora),
/// o cursor da próxima página (`null` quando não há mais) e se uma página adicional está sendo
/// buscada agora (`carregarMais` em andamento) — usado só para o indicador local do botão
/// "Carregar mais", não afeta o `AsyncValue` da tela inteira.
class PaginaResumosEstado {
  const PaginaResumosEstado({
    required this.itens,
    this.proximoCursor,
    this.carregandoMais = false,
  });

  final List<EmailSummary> itens;
  final String? proximoCursor;
  final bool carregandoMais;

  PaginaResumosEstado copyWith({
    List<EmailSummary>? itens,
    String? proximoCursor,
    bool limparCursor = false,
    bool? carregandoMais,
  }) {
    return PaginaResumosEstado(
      itens: itens ?? this.itens,
      proximoCursor: limparCursor ? null : (proximoCursor ?? this.proximoCursor),
      carregandoMais: carregandoMais ?? this.carregandoMais,
    );
  }
}

/// Carrega a caixa de entrada por páginas (`EmailSummaryRepository.listar`). `build` sempre busca
/// a primeira página — por isso `recarregar()` só precisa invalidar e reaguardar. `carregarMais`
/// concatena a página seguinte ao estado atual sem passar pelo ciclo de `build` (não deve acionar
/// o `loading` da tela inteira, só o indicador local `carregandoMais`).
///
/// Nota sobre a API do Riverpod: `flutter_riverpod`/`riverpod` 3.3.2 (versão travada em
/// `pubspec.lock`) não expõe uma classe `AutoDisposeAsyncNotifier` separada — a variante
/// `autoDispose` é só o builder estático `AsyncNotifierProvider.autoDispose` abaixo; a classe base
/// do notifier continua sendo sempre `AsyncNotifier` (ver
/// `~/.pub-cache/hosted/pub.dev/riverpod-3.3.2/lib/src/providers/async_notifier/orphan.dart` e
/// `builder.dart:AutoDisposeAsyncNotifierProviderBuilder`).
class EmailSummariesNotifier extends AsyncNotifier<PaginaResumosEstado> {
  @override
  Future<PaginaResumosEstado> build() async {
    final pagina = await ref.watch(emailSummaryRepositoryProvider).listar();
    return PaginaResumosEstado(itens: pagina.itens, proximoCursor: pagina.proximoCursor);
  }

  /// Recarrega do zero (página 1) — usado pelo pull-to-refresh, pelo retorno ao primeiro plano e
  /// pelo push de dados `inbox_atualizada`. `invalidateSelf` descarta o cache e `await future`
  /// garante que quem chamou `recarregar()` só resolve depois que os dados novos chegaram.
  Future<void> recarregar() async {
    ref.invalidateSelf();
    await future;
  }

  /// Busca a próxima página e concatena ao final da lista atual. No-op sem `proximoCursor` (já é
  /// a última página) ou se uma busca já está em andamento — evita disparos duplicados por toques
  /// repetidos no botão "Carregar mais". Em caso de erro, reverte só a flag `carregandoMais`,
  /// preservando os itens já carregados — quem chamou pode tentar de novo sem perder o que já tinha.
  Future<void> carregarMais() async {
    final atual = state.value;
    if (atual == null || atual.proximoCursor == null || atual.carregandoMais) return;
    state = AsyncData(atual.copyWith(carregandoMais: true));
    try {
      final pagina = await ref
          .read(emailSummaryRepositoryProvider)
          .listar(cursor: atual.proximoCursor);
      state = AsyncData(
        PaginaResumosEstado(
          itens: [...atual.itens, ...pagina.itens],
          proximoCursor: pagina.proximoCursor,
        ),
      );
    } catch (_) {
      state = AsyncData(atual.copyWith(carregandoMais: false));
    }
  }
}

final emailSummariesProvider =
    AsyncNotifierProvider.autoDispose<EmailSummariesNotifier, PaginaResumosEstado>(
  EmailSummariesNotifier.new,
);

final fcmTokenRepositoryProvider = Provider<FcmTokenRepository>((ref) {
  return FcmTokenRepository(ref.watch(apiClientProvider).dio);
});

final emailReplyRepositoryProvider = Provider<EmailReplyRepository>((ref) {
  return EmailReplyRepository(ref.watch(apiClientProvider).dio);
});
