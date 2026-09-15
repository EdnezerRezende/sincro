import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/emergency/emergency_providers.dart';
import 'package:sincro_mobile/features/emergency/emergency_repository.dart';
import 'package:sincro_mobile/features/emergency/emergency_sheet.dart';
import 'package:sincro_mobile/features/trusted_contacts/trusted_contact.dart';

const _contacts = [
  TrustedContact(id: 'c1', nome: 'Marina Souza', relacao: 'PSICOLOGO', whatsapp: '+5511999999999', prioridade: 0),
  TrustedContact(id: 'c2', nome: 'João Lima', relacao: 'FAMILIAR', whatsapp: '+5511988880000', prioridade: 0),
];

EmergencyRepository _repo(void Function(Map<String, dynamic>) onBody) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test'));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    final body = options.data as Map<String, dynamic>;
    onBody(body);
    final ids = (body['contactIds'] as List).cast<String>();
    handler.resolve(Response(
      requestOptions: options,
      statusCode: 201,
      data: ids
          .map((id) => {
                'contactId': id,
                'contactName': _contacts.firstWhere((c) => c.id == id).nome,
                'whatsapp': '+55',
                'message': 'Oi',
                'waUrl': 'https://wa.me/$id',
              })
          .toList(),
    ));
  }));
  return EmergencyRepository(dio);
}

Future<void> _pumpSheet(WidgetTester tester, EmergencyRepository repo, List<Uri> launched) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [emergencyRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showEmergencySheet(context, contacts: _contacts, launch: (uri) async => launched.add(uri)),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('starts with every contact selected and the default template', (tester) async {
    await _pumpSheet(tester, _repo((_) {}), []);

    expect(find.text('Avisar Rede de Apoio'), findsOneWidget);
    expect(find.text('Abrir WhatsApp · 1 de 2: Marina'), findsOneWidget);
    expect(find.textContaining('Oi {primeiro nome}, estou passando'), findsOneWidget);
  });

  testWidgets('unselecting everyone disables the CTA', (tester) async {
    await _pumpSheet(tester, _repo((_) {}), []);

    await tester.tap(find.text('Marina Souza'));
    await tester.tap(find.text('João Lima'));
    await tester.pump();

    final button = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Escolha quem avisar'));
    expect(button.onPressed, isNull);
  });

  testWidgets('sends selected ids and edited template, then walks the queue', (tester) async {
    Map<String, dynamic>? body;
    final launched = <Uri>[];
    await _pumpSheet(tester, _repo((b) => body = b), launched);

    await tester.tap(find.text('João Lima'));
    await tester.enterText(find.byType(TextField), 'Oi {primeiro nome}, pode me ligar?');
    await tester.tap(find.text('Abrir WhatsApp para Marina'));
    await tester.pumpAndSettle();

    expect(body!['contactIds'], ['c1']);
    expect(body!['template'], 'Oi {primeiro nome}, pode me ligar?');
    expect(launched.single.toString(), 'https://wa.me/c1');
    expect(find.text('Avisos abertos para 1 pessoa.'), findsOneWidget);
  });

  testWidgets('with two contacts shows the next step after the first launch', (tester) async {
    final launched = <Uri>[];
    await _pumpSheet(tester, _repo((_) {}), launched);

    await tester.tap(find.text('Abrir WhatsApp · 1 de 2: Marina'));
    await tester.pumpAndSettle();

    expect(launched.length, 1);
    expect(find.text('Enviado para Marina. Próximo: João'), findsOneWidget);
    expect(find.text('Continuar com João'), findsOneWidget);

    await tester.tap(find.text('Continuar com João'));
    await tester.pumpAndSettle();
    expect(launched.length, 2);
    expect(find.text('Avisos abertos para 2 pessoas.'), findsOneWidget);
  });

  testWidgets('"Restaurar padrão" puts the default template back', (tester) async {
    await _pumpSheet(tester, _repo((_) {}), []);
    await tester.enterText(find.byType(TextField), 'x');
    await tester.tap(find.text('Restaurar padrão'));
    await tester.pump();
    expect(find.textContaining('Oi {primeiro nome}, estou passando'), findsOneWidget);
  });
}
