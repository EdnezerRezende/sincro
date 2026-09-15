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
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

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

  testWidgets('when launch throws on the first contact, shows the error without crashing and keeps the CTA', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ProviderScope(
      overrides: [emergencyRepositoryProvider.overrideWithValue(_repo((_) {}))],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showEmergencySheet(
                context,
                contacts: _contacts,
                launch: (_) async => throw Exception('x'),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Abrir WhatsApp · 1 de 2: Marina'));
    await tester.pumpAndSettle();

    expect(find.text('Não foi possível abrir o WhatsApp.'), findsOneWidget);
    expect(find.text('Abrir WhatsApp · 1 de 2: Marina'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Abrir WhatsApp · 1 de 2: Marina'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('with more than 10 contacts, only the first 10 are selected by default', (tester) async {
    final manyContacts = List.generate(
      11,
      (i) => TrustedContact(
        id: 'c$i',
        nome: 'Contato$i',
        relacao: 'AMIGO',
        whatsapp: '+5511999${i.toString().padLeft(6, '0')}',
        prioridade: 0,
      ),
    );
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final body = options.data as Map<String, dynamic>;
      final ids = (body['contactIds'] as List).cast<String>();
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 201,
        data: ids
            .map((id) => {
                  'contactId': id,
                  'contactName': manyContacts.firstWhere((c) => c.id == id).nome,
                  'whatsapp': '+55',
                  'message': 'Oi',
                  'waUrl': 'https://wa.me/$id',
                })
            .toList(),
      ));
    }));
    final repo = EmergencyRepository(dio);

    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ProviderScope(
      overrides: [emergencyRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showEmergencySheet(context, contacts: manyContacts, launch: (_) async {}),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Abrir WhatsApp · 1 de 10: Contato0'), findsOneWidget);

    final checkboxes = tester.widgetList<CheckboxListTile>(find.byType(CheckboxListTile)).toList();
    expect(checkboxes.length, 11);
    final checkedCount = checkboxes.where((c) => c.value == true).length;
    expect(checkedCount, 10);
    expect(checkboxes.last.value, isFalse);

    await tester.ensureVisible(find.text('Contato10'));
    await tester.tap(find.text('Contato10'));
    await tester.pump();

    expect(find.text('Você pode avisar até 10 pessoas por vez.'), findsOneWidget);
    expect(find.text('Abrir WhatsApp · 1 de 10: Contato0'), findsOneWidget);
  });
}
