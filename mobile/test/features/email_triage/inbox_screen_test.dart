// Covers the "remove an e-mail from the inbox" bar: an accessible per-e-mail action (never
// swipe-only) that archives immediately (reversible in Gmail itself) or asks for confirmation
// before deleting (moves to Trash, still recoverable there for ~30 days), refreshes the visible
// list on success, and — when the account hasn't granted `gmail.modify` yet — surfaces a
// reconnect path instead of failing silently.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/features/email_triage/email_summary.dart';
import 'package:sincro_mobile/features/email_triage/email_summary_repository.dart';
import 'package:sincro_mobile/features/email_triage/email_triage_providers.dart';
import 'package:sincro_mobile/features/email_triage/gmail_connection_repository.dart';
import 'package:sincro_mobile/features/email_triage/inbox_screen.dart';

class _FakeEmailSummaryRepository extends EmailSummaryRepository {
  _FakeEmailSummaryRepository(List<EmailSummary> summaries, {this.arquivarError, this.excluirError})
    : _summaries = summaries,
      super(Dio());

  List<EmailSummary> _summaries;
  final Object? arquivarError;
  final Object? excluirError;
  int chamadasArquivar = 0;
  int chamadasExcluir = 0;

  @override
  Future<List<EmailSummary>> list() async => List.of(_summaries);

  @override
  Future<void> arquivar(String emailId) async {
    chamadasArquivar++;
    final erro = arquivarError;
    if (erro != null) throw erro;
    _summaries = _summaries.where((s) => s.id != emailId).toList();
  }

  @override
  Future<void> excluir(String emailId) async {
    chamadasExcluir++;
    final erro = excluirError;
    if (erro != null) throw erro;
    _summaries = _summaries.where((s) => s.id != emailId).toList();
  }
}

class _FakeGmailConnectionRepository extends GmailConnectionRepository {
  _FakeGmailConnectionRepository({this.disconnectError}) : super(Dio(), () => throw UnimplementedError());

  final Object? disconnectError;
  int chamadasConnect = 0;
  int chamadasDisconnect = 0;

  @override
  Future<void> connect() async {
    chamadasConnect++;
  }

  @override
  Future<void> disconnect() async {
    chamadasDisconnect++;
    final erro = disconnectError;
    if (erro != null) throw erro;
  }
}

DioException _forbidden(String path) => DioException(
  requestOptions: RequestOptions(path: path),
  response: Response(
    requestOptions: RequestOptions(path: path),
    statusCode: 403,
    data: {'message': 'Reconecte o Gmail para arquivar ou excluir e-mails por aqui.'},
  ),
);

final _email1 = EmailSummary(
  id: 'email-1',
  remetente: 'Banco <banco@example.com>',
  assunto: 'Fatura',
  resumoCurto: 'Fatura vence amanhã',
  categoria: 'PRECISA_ATENCAO',
  recebidoEm: DateTime.now().subtract(const Duration(hours: 1)),
);

final _email2 = EmailSummary(
  id: 'email-2',
  remetente: 'Newsletter <news@example.com>',
  assunto: 'Novidades da semana',
  resumoCurto: 'Confira as novidades',
  categoria: 'PODE_ESPERAR',
  recebidoEm: DateTime.now().subtract(const Duration(hours: 2)),
);

Widget _app(
  EmailSummaryRepository summaryRepository, {
  GmailConnectionRepository? connectionRepository,
  GmailConnectionStatus? status,
  // Alternativa a `status` para os casos em que o valor devolvido precisa mudar conforme o teste
  // avança (por exemplo, refletir uma chamada a `connect()` que já aconteceu) — `reconectarGmail`
  // releva o status via `ref.refresh(...future)`, que reexecuta este builder.
  GmailConnectionStatus Function()? statusBuilder,
}) {
  return ProviderScope(
    overrides: [
      emailSummaryRepositoryProvider.overrideWithValue(summaryRepository),
      if (connectionRepository != null)
        gmailConnectionRepositoryProvider.overrideWithValue(connectionRepository),
      // Sem este override, o menu da AppBar (`_GmailConnectionMenu`) dispararia uma chamada de
      // rede real via `apiClientProvider` só de observar `gmailConnectionStatusProvider` — o
      // padrão já usado em email_detail_screen_test.dart. Por padrão simula uma conta conectada
      // e já com o escopo `gmail.modify`, para não interferir nos testes de arquivar/excluir.
      gmailConnectionStatusProvider.overrideWith(
        (ref) async =>
            statusBuilder?.call() ??
            status ??
            const GmailConnectionStatus(connected: true, temEscopoModificacao: true),
      ),
    ],
    child: MaterialApp(theme: sincroLightTheme, home: const InboxScreen()),
  );
}

// Cada e-mail tem seu próprio botão "Mais ações" com o mesmo ícone (`more_vert`) usado também
// pelo menu da conexão com o Gmail na AppBar — `byTooltip` desambigua pelo texto acessível de
// cada botão em vez de depender da ordem dos widgets na árvore.
Future<void> _abrirMenuEArquivarOuExcluir(WidgetTester tester, String acao) async {
  await tester.tap(find.byTooltip('Mais ações').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(acao));
  await tester.pumpAndSettle();
}

Future<void> _abrirMenuDaConexao(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Opções da conexão com o Gmail'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('archiving an e-mail removes it from the list right away', (tester) async {
    final repo = _FakeEmailSummaryRepository([_email1, _email2]);

    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    expect(find.text('Fatura'), findsOneWidget);

    await _abrirMenuEArquivarOuExcluir(tester, 'Arquivar');

    expect(repo.chamadasArquivar, 1);
    expect(find.text('Fatura'), findsNothing);
    expect(find.text('E-mail arquivado.'), findsOneWidget);
  });

  testWidgets('deleting an e-mail asks for confirmation before acting, then removes it on confirm', (
    tester,
  ) async {
    final repo = _FakeEmailSummaryRepository([_email1, _email2]);

    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await _abrirMenuEArquivarOuExcluir(tester, 'Excluir');

    // Confirmation dialog shown; nothing deleted yet.
    expect(repo.chamadasExcluir, 0);
    expect(find.text('Excluir e-mail?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Excluir'));
    await tester.pumpAndSettle();

    expect(repo.chamadasExcluir, 1);
    expect(find.text('Fatura'), findsNothing);
    expect(find.text('E-mail movido para a lixeira.'), findsOneWidget);
  });

  testWidgets('cancelling the delete confirmation keeps the e-mail in the list', (tester) async {
    final repo = _FakeEmailSummaryRepository([_email1, _email2]);

    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await _abrirMenuEArquivarOuExcluir(tester, 'Excluir');
    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await tester.pumpAndSettle();

    expect(repo.chamadasExcluir, 0);
    expect(find.text('Fatura'), findsOneWidget);
  });

  testWidgets(
    'a missing gmail.modify scope (403) on archive surfaces a reconnect action instead of failing silently',
    (tester) async {
      final repo = _FakeEmailSummaryRepository(
        [_email1],
        arquivarError: _forbidden('/resumos-email/email-1/arquivar'),
      );
      final connectionRepo = _FakeGmailConnectionRepository();

      await tester.pumpWidget(_app(repo, connectionRepository: connectionRepo));
      await tester.pumpAndSettle();

      await _abrirMenuEArquivarOuExcluir(tester, 'Arquivar');

      expect(find.text('Reconecte o Gmail para arquivar e-mails por aqui.'), findsOneWidget);
      final reconectarAction = find.widgetWithText(SnackBarAction, 'Reconectar');
      expect(reconectarAction, findsOneWidget);

      await tester.tap(reconectarAction);
      await tester.pumpAndSettle();

      expect(connectionRepo.chamadasConnect, 1);
      // The e-mail is still there — arquivar never succeeded.
      expect(find.text('Fatura'), findsOneWidget);
    },
  );

  testWidgets(
    'a missing gmail.modify scope (403) on delete (after confirming) surfaces a reconnect action',
    (tester) async {
      final repo = _FakeEmailSummaryRepository(
        [_email1],
        excluirError: _forbidden('/resumos-email/email-1/excluir'),
      );
      final connectionRepo = _FakeGmailConnectionRepository();

      await tester.pumpWidget(_app(repo, connectionRepository: connectionRepo));
      await tester.pumpAndSettle();

      await _abrirMenuEArquivarOuExcluir(tester, 'Excluir');
      await tester.tap(find.widgetWithText(FilledButton, 'Excluir'));
      await tester.pumpAndSettle();

      expect(find.text('Reconecte o Gmail para excluir e-mails por aqui.'), findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, 'Reconectar'), findsOneWidget);
      expect(find.text('Fatura'), findsOneWidget);
    },
  );

  group('Gmail connection menu (AppBar)', () {
    testWidgets('offers to disconnect Gmail, asks for confirmation, then calls the repository', (
      tester,
    ) async {
      final repo = _FakeEmailSummaryRepository([_email1]);
      final connectionRepo = _FakeGmailConnectionRepository();

      await tester.pumpWidget(_app(repo, connectionRepository: connectionRepo));
      await tester.pumpAndSettle();

      await _abrirMenuDaConexao(tester);
      expect(find.text('Desconectar Gmail'), findsOneWidget);

      await tester.tap(find.text('Desconectar Gmail'));
      await tester.pumpAndSettle();

      // Confirmation dialog shown; nothing disconnected yet.
      expect(connectionRepo.chamadasDisconnect, 0);
      expect(find.text('Desconectar Gmail?'), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Desconectar'));
      await tester.pumpAndSettle();

      expect(connectionRepo.chamadasDisconnect, 1);
      expect(find.text('Gmail desconectado.'), findsOneWidget);
    });

    testWidgets('cancelling the disconnect confirmation never calls the repository', (tester) async {
      final repo = _FakeEmailSummaryRepository([_email1]);
      final connectionRepo = _FakeGmailConnectionRepository();

      await tester.pumpWidget(_app(repo, connectionRepository: connectionRepo));
      await tester.pumpAndSettle();

      await _abrirMenuDaConexao(tester);
      await tester.tap(find.text('Desconectar Gmail'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
      await tester.pumpAndSettle();

      expect(connectionRepo.chamadasDisconnect, 0);
    });

    testWidgets(
      'when the connection is missing the gmail.modify scope, the menu offers to grant it by reconnecting',
      (tester) async {
        final repo = _FakeEmailSummaryRepository([_email1]);
        final connectionRepo = _FakeGmailConnectionRepository();

        await tester.pumpWidget(
          _app(
            repo,
            connectionRepository: connectionRepo,
            status: const GmailConnectionStatus(connected: true, temEscopoModificacao: false),
          ),
        );
        await tester.pumpAndSettle();

        await _abrirMenuDaConexao(tester);
        expect(find.text('Permitir arquivar e excluir e-mails'), findsOneWidget);
        // "Desconectar Gmail" continua disponível ao mesmo tempo — não é uma escolha excludente.
        expect(find.text('Desconectar Gmail'), findsOneWidget);
      },
    );

    testWidgets(
      'granting the modify scope: only announces success after RE-READING the status post-reconnect '
      'and confirming temEscopoModificacao — never just because connect() did not throw',
      (tester) async {
        final repo = _FakeEmailSummaryRepository([_email1]);
        final connectionRepo = _FakeGmailConnectionRepository();

        await tester.pumpWidget(
          _app(
            repo,
            connectionRepository: connectionRepo,
            // O escopo só passa a `true` DEPOIS que `connect()` foi chamado — simula o backend
            // relendo a concessão real do Google (granular, pode ter sido negada) em vez de o
            // cliente assumir sucesso só porque a chamada de reconexão não lançou.
            statusBuilder: () => GmailConnectionStatus(
              connected: true,
              temEscopoModificacao: connectionRepo.chamadasConnect > 0,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _abrirMenuDaConexao(tester);
        expect(find.text('Permitir arquivar e excluir e-mails'), findsOneWidget);

        await tester.tap(find.text('Permitir arquivar e excluir e-mails'));
        await tester.pumpAndSettle();

        expect(connectionRepo.chamadasConnect, 1);
        expect(
          find.text('Gmail reconectado. Agora você pode arquivar e excluir e-mails por aqui.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'if the Google consent still withholds the modify scope after reconnecting, the app does NOT '
      'announce success — it says calmly that the permission is missing and offers to try again',
      (tester) async {
        final repo = _FakeEmailSummaryRepository([_email1]);
        final connectionRepo = _FakeGmailConnectionRepository();

        await tester.pumpWidget(
          _app(
            repo,
            connectionRepository: connectionRepo,
            // Mesmo depois de `connect()` ter sido chamado (e não ter lançado), o escopo continua
            // ausente — a pessoa desmarcou `gmail.modify` na tela de consentimento do Google, ou
            // o client OAuth nem está aprovado para esse escopo restrito.
            statusBuilder: () =>
                const GmailConnectionStatus(connected: true, temEscopoModificacao: false),
          ),
        );
        await tester.pumpAndSettle();

        await _abrirMenuDaConexao(tester);
        await tester.tap(find.text('Permitir arquivar e excluir e-mails'));
        await tester.pumpAndSettle();

        expect(connectionRepo.chamadasConnect, 1);
        expect(
          find.text('Gmail reconectado. Agora você pode arquivar e excluir e-mails por aqui.'),
          findsNothing,
        );
        expect(
          find.text(
            'A conexão foi feita, mas a permissão para arquivar e excluir e-mails não foi '
            'concedida. Você pode tentar de novo e, na tela do Google, deixar essa permissão '
            'marcada.',
          ),
          findsOneWidget,
        );
        // O menu continua oferecendo a mesma ação — não vira um beco sem saída dentro do fluxo.
        await _abrirMenuDaConexao(tester);
        expect(find.text('Permitir arquivar e excluir e-mails'), findsOneWidget);
      },
    );

    testWidgets('when Gmail is not connected, the menu offers to reconnect instead of disconnect', (
      tester,
    ) async {
      final repo = _FakeEmailSummaryRepository([]);
      final connectionRepo = _FakeGmailConnectionRepository();

      await tester.pumpWidget(
        _app(
          repo,
          connectionRepository: connectionRepo,
          status: const GmailConnectionStatus(connected: false),
        ),
      );
      await tester.pumpAndSettle();

      await _abrirMenuDaConexao(tester);
      expect(find.text('Reconectar Gmail'), findsOneWidget);
      expect(find.text('Desconectar Gmail'), findsNothing);

      await tester.tap(find.text('Reconectar Gmail'));
      await tester.pumpAndSettle();

      expect(connectionRepo.chamadasConnect, 1);
    });
  });
}
