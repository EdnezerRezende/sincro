// Covers the "remove an e-mail from the inbox" bar: an accessible per-e-mail action (never
// swipe-only) that archives immediately (reversible in Gmail itself) or asks for confirmation
// before deleting (moves to Trash, still recoverable there for ~30 days), refreshes the visible
// list on success, and — when the account hasn't granted `gmail.modify` yet — surfaces a
// reconnect path instead of failing silently.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/features/email_triage/email_summary.dart';
import 'package:sincro_mobile/features/email_triage/email_summary_repository.dart'
    show EmailSummaryRepository, PaginaResumos;
import 'package:sincro_mobile/features/email_triage/email_triage_providers.dart';
import 'package:sincro_mobile/features/email_triage/gmail_connection_repository.dart';
import 'package:sincro_mobile/features/email_triage/inbox_screen.dart';

class _FakeEmailSummaryRepository extends EmailSummaryRepository {
  _FakeEmailSummaryRepository(
    List<EmailSummary> summaries, {
    this.arquivarError,
    this.excluirError,
    this.sincronizarError,
    this.proximoCursor,
    this.paginaCarregarMais,
  }) : _summaries = summaries,
       super(Dio());

  List<EmailSummary> _summaries;
  final Object? arquivarError;
  final Object? excluirError;
  final Object? sincronizarError;
  // Cursor devolvido pela primeira página (sem `cursor`) — controla se a tela mostra
  // "Carregar mais". `null` (padrão) = página única, sem botão.
  String? proximoCursor;
  // Página devolvida quando `listar` é chamado COM cursor, ou seja, por `carregarMais`.
  PaginaResumos? paginaCarregarMais;

  int chamadasArquivar = 0;
  int chamadasExcluir = 0;
  int chamadasSincronizar = 0;
  int chamadasListar = 0;
  int chamadasCarregarMais = 0;
  // Registro na ordem em que `sincronizar`/`listar` foram chamados — prova que o pull-to-refresh
  // sincroniza com o backend ANTES de reler a lista local, nunca o contrário.
  final List<String> ordemChamadas = [];

  @override
  Future<List<EmailSummary>> list() async => List.of(_summaries);

  @override
  Future<PaginaResumos> listar({String? cursor, int limite = 50}) async {
    ordemChamadas.add('listar');
    chamadasListar++;
    if (cursor != null) {
      chamadasCarregarMais++;
      return paginaCarregarMais ?? const PaginaResumos(itens: [], proximoCursor: null);
    }
    return PaginaResumos(itens: List.of(_summaries), proximoCursor: proximoCursor);
  }

  @override
  Future<void> sincronizar() async {
    ordemChamadas.add('sincronizar');
    chamadasSincronizar++;
    final erro = sincronizarError;
    if (erro != null) throw erro;
  }

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

final _email3 = EmailSummary(
  id: 'email-3',
  remetente: 'Academia <academia@example.com>',
  assunto: 'Mensalidade renovada',
  resumoCurto: 'Sua mensalidade foi renovada',
  categoria: 'PODE_ESPERAR',
  recebidoEm: DateTime.now().subtract(const Duration(hours: 3)),
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
            // `ultimaSincronizacao` não-nula por padrão: a maioria dos testes deste arquivo
            // simula uma conta já sincronizada há tempos, não o momento exato da primeira
            // sincronização — sem isso, qualquer cenário em que a lista fique momentaneamente
            // vazia cairia sem querer no estado "Sincronizando…" e deixaria um `Timer.periodic`
            // pendente ao final do teste.
            GmailConnectionStatus(
              connected: true,
              temEscopoModificacao: true,
              ultimaSincronizacao: DateTime(2026, 1, 1),
            ),
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

  group('Puxar para atualizar (sincronizar)', () {
    testWidgets('sincroniza com o backend ANTES de reler a lista local', (tester) async {
      final repo = _FakeEmailSummaryRepository([_email1, _email2]);

      await tester.pumpWidget(_app(repo));
      await tester.pumpAndSettle();
      expect(repo.ordemChamadas, ['listar']);

      final refreshState = tester.state<RefreshIndicatorState>(
        find.byType(RefreshIndicator),
      );
      unawaited(refreshState.show());
      await tester.pumpAndSettle();

      expect(repo.ordemChamadas, ['listar', 'sincronizar', 'listar']);
      expect(repo.chamadasSincronizar, 1);
      expect(repo.chamadasListar, 2);
    });

    testWidgets(
      '202 do backend (sincronização recente ou já em andamento) não é tratado como erro',
      (tester) async {
        // `sincronizar()` nunca lança para 2xx — inclusive 202 — então este teste apenas garante
        // que o refresh completa normalmente (relendo a lista) quando o repositório não lança.
        final repo = _FakeEmailSummaryRepository([_email1]);

        await tester.pumpWidget(_app(repo));
        await tester.pumpAndSettle();

        final refreshState = tester.state<RefreshIndicatorState>(
          find.byType(RefreshIndicator),
        );
        unawaited(refreshState.show());
        await tester.pumpAndSettle();

        expect(find.text('Não foi possível carregar seus e-mails.'), findsNothing);
        expect(repo.chamadasListar, 2);
      },
    );

    testWidgets(
      '403 ao sincronizar (Gmail não conectado) mostra o CTA de reconexão com a cópia da caixa',
      (tester) async {
        final repo = _FakeEmailSummaryRepository(
          [_email1],
          sincronizarError: _forbidden('/resumos-email/sincronizar'),
        );
        final connectionRepo = _FakeGmailConnectionRepository();

        await tester.pumpWidget(_app(repo, connectionRepository: connectionRepo));
        await tester.pumpAndSettle();

        final refreshState = tester.state<RefreshIndicatorState>(
          find.byType(RefreshIndicator),
        );
        unawaited(refreshState.show());
        await tester.pumpAndSettle();

        expect(find.text('Reconecte o Gmail para atualizar a caixa.'), findsOneWidget);
        expect(find.widgetWithText(SnackBarAction, 'Reconectar'), findsOneWidget);
        // A falha na sincronização não impede a releitura da lista local no `finally`.
        expect(repo.chamadasListar, 2);

        await tester.tap(find.widgetWithText(SnackBarAction, 'Reconectar'));
        await tester.pumpAndSettle();

        expect(connectionRepo.chamadasConnect, 1);
      },
    );
  });

  group('Carregar mais', () {
    testWidgets('aparece só quando há próxima página e busca a página seguinte ao ser tocado', (
      tester,
    ) async {
      final repo = _FakeEmailSummaryRepository(
        [_email1, _email2],
        proximoCursor: 'c1',
        paginaCarregarMais: PaginaResumos(itens: [_email3], proximoCursor: null),
      );

      await tester.pumpWidget(_app(repo));
      await tester.pumpAndSettle();

      expect(find.text('Carregar mais'), findsOneWidget);
      expect(find.text('Mensalidade renovada'), findsNothing);

      await tester.tap(find.text('Carregar mais'));
      await tester.pumpAndSettle();

      expect(repo.chamadasCarregarMais, 1);
      expect(find.text('Mensalidade renovada'), findsOneWidget);
      // A página seguinte não tem `proximoCursor` — o botão some.
      expect(find.text('Carregar mais'), findsNothing);
    });

    testWidgets('não aparece quando a primeira página não tem próximo cursor', (tester) async {
      final repo = _FakeEmailSummaryRepository([_email1, _email2]);

      await tester.pumpWidget(_app(repo));
      await tester.pumpAndSettle();

      expect(find.text('Carregar mais'), findsNothing);
    });
  });

  group('Revalidação ao retomar o app', () {
    testWidgets('AppLifecycleState.resumed dentro do intervalo mínimo NÃO revalida', (
      tester,
    ) async {
      final repo = _FakeEmailSummaryRepository([_email1]);

      await tester.pumpWidget(_app(repo));
      await tester.pumpAndSettle();
      expect(repo.chamadasListar, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(
        repo.chamadasListar,
        1,
        reason: 'Retomar o app dentro do intervalo mínimo não deveria revalidar',
      );
    });

    // Único teste "lento" do arquivo (mesmo padrão de `calendar/revalidation_test.dart`): usa
    // `tester.runAsync` para deixar ~31s de tempo REAL decorrerem, porque
    // `didChangeAppLifecycleState` compara `DateTime.now()` (relógio real) contra
    // `kRevalidationMinInterval` — não há seam de injeção de relógio no widget.
    testWidgets(
      'AppLifecycleState.resumed após o intervalo mínimo já ter decorrido revalida',
      (tester) async {
        final repo = _FakeEmailSummaryRepository([_email1]);

        await tester.pumpWidget(_app(repo));
        await tester.pumpAndSettle();
        expect(repo.chamadasListar, 1);

        await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 31)));

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpAndSettle();

        expect(
          repo.chamadasListar,
          2,
          reason: 'Retomar o app depois do intervalo mínimo deveria revalidar a caixa',
        );
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });

  group('Estado "Sincronizando sua caixa…"', () {
    const textoSincronizando = 'Sincronizando sua caixa… isso leva alguns segundos.';
    const textoVazio = 'Nenhum e-mail novo por aqui.';

    testWidgets(
      'conectado sem ultimaSincronizacao mostra o indicador e relê a cada 5s; esgotados 60s cai no vazio padrão',
      (tester) async {
        final repo = _FakeEmailSummaryRepository([]);

        await tester.pumpWidget(
          _app(
            repo,
            status: const GmailConnectionStatus(
              connected: true,
              temEscopoModificacao: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(textoSincronizando), findsOneWidget);
        expect(find.text(textoVazio), findsNothing);

        // 11 tentativas (55s): ainda dentro do prazo, continua tentando.
        for (var i = 0; i < 11; i++) {
          await tester.pump(const Duration(seconds: 5));
        }
        expect(find.text(textoSincronizando), findsOneWidget);
        expect(repo.chamadasListar, greaterThanOrEqualTo(11));

        // 12ª tentativa (60s): esgota o prazo e cai no estado vazio comum.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();

        expect(find.text(textoSincronizando), findsNothing);
        expect(find.text(textoVazio), findsOneWidget);
      },
    );

    testWidgets(
      'conectado com ultimaSincronizacao já preenchida e caixa vazia mostra o vazio padrão direto',
      (tester) async {
        final repo = _FakeEmailSummaryRepository([]);

        await tester.pumpWidget(
          _app(
            repo,
            status: GmailConnectionStatus(
              connected: true,
              temEscopoModificacao: true,
              ultimaSincronizacao: DateTime(2026, 1, 1),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(textoSincronizando), findsNothing);
        expect(find.text(textoVazio), findsOneWidget);
      },
    );

    testWidgets('o timer é cancelado ao a tela ser removida da árvore', (tester) async {
      final repo = _FakeEmailSummaryRepository([]);

      await tester.pumpWidget(
        _app(
          repo,
          status: const GmailConnectionStatus(connected: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(textoSincronizando), findsOneWidget);

      // Substitui a árvore inteira: dispõe o `InboxScreen`. Se o `Timer.periodic` não tivesse
      // sido cancelado no `dispose`, o `pumpAndSettle` abaixo (ou o fim do teste) lançaria "A
      // Timer is still pending" pela binding de teste.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}
