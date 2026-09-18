import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/email_triage/email_summary.dart';
import 'package:sincro_mobile/features/email_triage/email_summary_repository.dart';
import 'package:sincro_mobile/features/email_triage/email_triage_providers.dart';
import 'package:sincro_mobile/features/email_triage/gmail_connection_repository.dart';
import 'package:sincro_mobile/features/email_triage/inbox_screen.dart';

class _FakeRepo extends EmailSummaryRepository {
  _FakeRepo() : super(Dio());
  @override
  Future<PaginaResumos> listar({String? cursor, int limite = 50}) async {
    return const PaginaResumos(itens: [], proximoCursor: null);
  }
  @override
  Future<List<EmailSummary>> list() async => [];
}

void main() {
  testWidgets('debug', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          emailSummaryRepositoryProvider.overrideWithValue(_FakeRepo()),
          gmailConnectionStatusProvider.overrideWith(
            (ref) async => const GmailConnectionStatus(connected: true, temEscopoModificacao: true),
          ),
        ],
        child: const MaterialApp(home: InboxScreen()),
      ),
    );
    await tester.pump();
    print('AFTER FIRST PUMP:');
    print(find.text('Sincronizando sua caixa… isso leva alguns segundos.').evaluate().length);
    print(find.text('Nenhum e-mail novo por aqui.').evaluate().length);
    print(find.byType(CircularProgressIndicator).evaluate().length);

    await tester.pumpAndSettle();
    print('AFTER SETTLE:');
    print(find.text('Sincronizando sua caixa… isso leva alguns segundos.').evaluate().length);
    print(find.text('Nenhum e-mail novo por aqui.').evaluate().length);
    print(find.byType(CircularProgressIndicator).evaluate().length);
  });
}
