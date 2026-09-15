import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/home/emergency_button.dart';
import 'package:sincro_mobile/features/trusted_contacts/trusted_contacts_providers.dart';
import 'package:sincro_mobile/features/trusted_contacts/trusted_contacts_repository.dart';

TrustedContactsRepository _repoWith(List<Map<String, dynamic>> contacts) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test'));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) => h.resolve(Response(requestOptions: o, statusCode: 200, data: contacts))));
  return TrustedContactsRepository(dio);
}

Future<void> _pump(WidgetTester tester, TrustedContactsRepository repo) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [trustedContactsRepositoryProvider.overrideWithValue(repo)],
    child: const MaterialApp(home: Scaffold(body: EmergencyButton())),
  ));
}

void main() {
  testWidgets('without contacts shows the existing hint snackbar', (tester) async {
    await _pump(tester, _repoWith([]));
    await tester.tap(find.text('Avisar Rede de Apoio'));
    await tester.pumpAndSettle();
    expect(find.text('Cadastre um contato de confiança primeiro.'), findsOneWidget);
  });

  testWidgets('with contacts opens the sheet', (tester) async {
    await _pump(tester, _repoWith([
      {'id': 'c1', 'nome': 'Marina Souza', 'relacao': 'PSICOLOGO', 'whatsapp': '+5511999999999', 'prioridade': 0},
    ]));
    await tester.tap(find.text('Avisar Rede de Apoio'));
    await tester.pumpAndSettle();
    expect(find.text('Quem avisar'), findsOneWidget);
    expect(find.text('Abrir WhatsApp para Marina'), findsOneWidget);
  });
}
