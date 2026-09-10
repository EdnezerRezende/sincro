// Covers the "open an e-mail" bar: the detail screen must show the e-mail itself (sender,
// subject, date, body) without depending on any LLM call, and the AI reply suggestion must be a
// separate, on-demand action whose failure never blocks reading nor writing a reply from scratch.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/features/email_triage/email_body.dart';
import 'package:sincro_mobile/features/email_triage/email_detail_screen.dart';
import 'package:sincro_mobile/features/email_triage/email_reply_repository.dart';
import 'package:sincro_mobile/features/email_triage/email_summary.dart';
import 'package:sincro_mobile/features/email_triage/email_summary_repository.dart';
import 'package:sincro_mobile/features/email_triage/email_triage_providers.dart';
import 'package:sincro_mobile/features/email_triage/gmail_connection_repository.dart';
import 'package:sincro_mobile/features/email_triage/rascunhos_email.dart';

class _FakeEmailSummaryRepository extends EmailSummaryRepository {
  _FakeEmailSummaryRepository({this.corpoResult, this.corpoEhPreview = false, this.corpoError})
    : super(Dio());

  final String? corpoResult;
  final bool corpoEhPreview;
  final Object? corpoError;
  int chamadasConteudo = 0;

  @override
  Future<EmailBody> conteudo(String emailId) async {
    chamadasConteudo++;
    final erro = corpoError;
    if (erro != null) throw erro;
    return EmailBody(corpo: corpoResult ?? '', ehPreview: corpoEhPreview);
  }
}

class _FakeEmailReplyRepository extends EmailReplyRepository {
  _FakeEmailReplyRepository({this.rascunhosResult, this.rascunhosError}) : super(Dio());

  final RascunhosEmail? rascunhosResult;
  final Object? rascunhosError;
  int chamadasRascunhos = 0;

  @override
  Future<RascunhosEmail> gerarRascunhos(String emailId) async {
    chamadasRascunhos++;
    final erro = rascunhosError;
    if (erro != null) throw erro;
    final resultado = rascunhosResult;
    if (resultado != null) return resultado;
    return const RascunhosEmail(direto: 'd', formal: 'f', padrao: 'p');
  }

  @override
  Future<EnvioResultado> enviar(String emailId, String texto) async {
    return const EnvioResultado(enviado: true);
  }
}

final _summary = EmailSummary(
  id: 'email-1',
  remetente: 'Carlos <carlos@example.com>',
  assunto: 'Prazo do relatório',
  resumoCurto: 'Pergunta sobre prazo',
  categoria: 'PRECISA_ATENCAO',
  recebidoEm: DateTime(2026, 9, 1, 10, 30),
);

Widget _app({
  required EmailSummaryRepository summaryRepository,
  required EmailReplyRepository replyRepository,
  bool temEscopoEnvio = true,
}) {
  return ProviderScope(
    overrides: [
      emailSummaryRepositoryProvider.overrideWithValue(summaryRepository),
      emailReplyRepositoryProvider.overrideWithValue(replyRepository),
      gmailConnectionStatusProvider.overrideWith(
        (ref) async => GmailConnectionStatus(
          connected: true,
          gmailEmail: 'ana@exemplo.com',
          temEscopoEnvio: temEscopoEnvio,
          temEscopoAgenda: true,
        ),
      ),
    ],
    child: MaterialApp(
      theme: sincroLightTheme,
      home: EmailDetailScreen(summary: _summary),
    ),
  );
}

void main() {
  testWidgets('shows sender, subject, date and body once the content loads — no LLM involved', (
    tester,
  ) async {
    final summaryRepo = _FakeEmailSummaryRepository(corpoResult: 'Qual o prazo da entrega, por favor?');
    final replyRepo = _FakeEmailReplyRepository();

    await tester.pumpWidget(_app(summaryRepository: summaryRepo, replyRepository: replyRepo));
    await tester.pumpAndSettle();

    expect(find.text('Prazo do relatório'), findsWidgets);
    expect(find.text('De: Carlos <carlos@example.com>'), findsOneWidget);
    expect(find.text('Qual o prazo da entrega, por favor?'), findsOneWidget);

    // The old bug: opening an e-mail used to trigger the draft POST automatically. It must not.
    expect(replyRepo.chamadasRascunhos, 0);
  });

  testWidgets(
    'when the backend could only fall back to a short Gmail snippet, the screen says so instead '
    'of presenting the truncated text as if it were the whole message',
    (tester) async {
      final summaryRepo = _FakeEmailSummaryRepository(
        corpoResult: 'Um trecho bem curto…',
        corpoEhPreview: true,
      );
      final replyRepo = _FakeEmailReplyRepository();

      await tester.pumpWidget(_app(summaryRepository: summaryRepo, replyRepository: replyRepo));
      await tester.pumpAndSettle();

      expect(find.text('Um trecho bem curto…'), findsOneWidget);
      expect(
        find.textContaining('Não foi possível carregar o texto completo deste e-mail'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a normal e-mail (plain-text or HTML converted server-side) never shows the snippet warning',
    (tester) async {
      final summaryRepo = _FakeEmailSummaryRepository(
        corpoResult: 'Corpo completo, legível, convertido a partir do HTML original.',
      );
      final replyRepo = _FakeEmailReplyRepository();

      await tester.pumpWidget(_app(summaryRepository: summaryRepo, replyRepository: replyRepo));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Não foi possível carregar o texto completo deste e-mail'),
        findsNothing,
      );
    },
  );

  testWidgets('shows an empty-body message instead of a blank screen', (tester) async {
    final summaryRepo = _FakeEmailSummaryRepository(corpoResult: '');
    final replyRepo = _FakeEmailReplyRepository();

    await tester.pumpWidget(_app(summaryRepository: summaryRepo, replyRepository: replyRepo));
    await tester.pumpAndSettle();

    expect(find.text('Este e-mail não tem conteúdo de texto.'), findsOneWidget);
  });

  testWidgets('shows a retry action (never a dead screen) when loading the body fails', (
    tester,
  ) async {
    final summaryRepo = _FakeEmailSummaryRepository(corpoError: Exception('falha de rede'));
    final replyRepo = _FakeEmailReplyRepository();

    await tester.pumpWidget(_app(summaryRepository: summaryRepo, replyRepository: replyRepo));
    await tester.pumpAndSettle();

    expect(find.text('Não foi possível carregar o e-mail agora.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Tentar novamente'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Tentar novamente'));
    await tester.pumpAndSettle();

    expect(summaryRepo.chamadasConteudo, 2);
  });

  testWidgets(
    'the AI suggestion is on-demand: its failure surfaces locally and never blocks reading or '
    'writing a reply from scratch',
    (tester) async {
      final summaryRepo = _FakeEmailSummaryRepository(corpoResult: 'Corpo do e-mail original.');
      final replyRepo = _FakeEmailReplyRepository(rascunhosError: Exception('IA indisponível'));

      await tester.pumpWidget(_app(summaryRepository: summaryRepo, replyRepository: replyRepo));
      await tester.pumpAndSettle();

      // Body is visible and the send button is present (user can already write from scratch).
      expect(find.text('Corpo do e-mail original.'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Enviar'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Sugerir resposta'));
      await tester.pump();
      await tester.pumpAndSettle();

      // The failure is local — the e-mail body stays visible the whole time.
      expect(find.text('Corpo do e-mail original.'), findsOneWidget);
      expect(find.text('Não foi possível gerar sugestões agora.'), findsOneWidget);

      // Composing from scratch still works: typing enables "Enviar".
      await tester.enterText(find.byType(TextField), 'Envio até amanhã.');
      await tester.pump();
      final enviarButton = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Enviar'));
      expect(enviarButton.onPressed, isNotNull);
    },
  );

  testWidgets('a successful suggestion fills the reply text when a tone chip is tapped', (
    tester,
  ) async {
    final summaryRepo = _FakeEmailSummaryRepository(corpoResult: 'Corpo do e-mail original.');
    final replyRepo = _FakeEmailReplyRepository(
      rascunhosResult: const RascunhosEmail(direto: 'Envio amanhã.', formal: 'Prezado, envio amanhã.', padrao: 'Ok, envio amanhã.'),
    );

    await tester.pumpWidget(_app(summaryRepository: summaryRepo, replyRepository: replyRepo));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Sugerir resposta'));
    await tester.pumpAndSettle();

    expect(replyRepo.chamadasRascunhos, 1);
    await tester.tap(find.widgetWithText(ActionChip, 'Direto'));
    await tester.pump();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller?.text, 'Envio amanhã.');
  });

  testWidgets('without the send scope, shows a reconnect panel but still shows the e-mail body', (
    tester,
  ) async {
    final summaryRepo = _FakeEmailSummaryRepository(corpoResult: 'Corpo do e-mail original.');
    final replyRepo = _FakeEmailReplyRepository();

    await tester.pumpWidget(
      _app(summaryRepository: summaryRepo, replyRepository: replyRepo, temEscopoEnvio: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('Corpo do e-mail original.'), findsOneWidget);
    expect(find.text('Reconecte o Gmail para responder por aqui.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}
