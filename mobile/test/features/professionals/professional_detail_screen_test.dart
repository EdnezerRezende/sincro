import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/professionals/professional.dart';
import 'package:sincro_mobile/features/professionals/professional_detail_screen.dart';
import 'package:sincro_mobile/features/trusted_contacts/trusted_contacts_providers.dart';
import 'package:sincro_mobile/features/trusted_contacts/trusted_contacts_repository.dart';

Professional _profissional({required List<String> tags, required String telefone}) => Professional(
    id: 'p1', nome: 'Helena Prado', tags: tags, cidade: 'São Paulo', latitude: 0, longitude: 0, telefone: telefone, bio: 'Bio', ativo: true);

TrustedContactsRepository _repoVazio() {
  final dio = Dio(BaseOptions(baseUrl: 'http://test'));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) => h.resolve(Response(requestOptions: o, statusCode: 200, data: []))));
  return TrustedContactsRepository(dio);
}

void main() {
  test('buildWhatsAppUrl strips all non-digit characters', () {
    expect(buildWhatsAppUrl('+55 (11) 99999-9999'), 'https://wa.me/5511999999999');
  });

  test('buildTelUrl keeps a leading plus but strips other formatting', () {
    expect(buildTelUrl('+55 (11) 99999-9999'), 'tel:+5511999999999');
  });

  testWidgets('"Adicionar à rede de apoio" creates a trusted contact with the mapped relation', (tester) async {
    Map<String, dynamic>? body;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      if (o.method == 'POST') body = o.data as Map<String, dynamic>;
      h.resolve(Response(requestOptions: o, statusCode: o.method == 'POST' ? 201 : 200, data: o.method == 'POST' ? {} : []));
    }));

    await tester.pumpWidget(ProviderScope(
      overrides: [trustedContactsRepositoryProvider.overrideWithValue(TrustedContactsRepository(dio))],
      child: MaterialApp(home: ProfessionalDetailScreen(profissional: _profissional(tags: ['Psicólogo'], telefone: '+5511999990000'))),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Adicionar à rede de apoio'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Adicionar'));
    await tester.pumpAndSettle();

    expect(body, {
      'nome': 'Helena Prado', 'relacao': 'PSICOLOGO', 'whatsapp': '+5511999990000', 'prioridade': 0, 'consentimentoAceito': true,
    });
    expect(find.text('Adicionado à sua rede de apoio.'), findsOneWidget);
  });

  testWidgets('button is disabled when the phone is not a valid WhatsApp number', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [trustedContactsRepositoryProvider.overrideWithValue(_repoVazio())],
      child: MaterialApp(home: ProfessionalDetailScreen(profissional: _profissional(tags: ['Psicólogo'], telefone: '11 3333-0000'))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Telefone do profissional em formato inválido.'), findsOneWidget);
  });

  testWidgets('shows "Já está na sua rede de apoio" when a contact with the same whatsapp exists', (tester) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) => h.resolve(Response(requestOptions: o, statusCode: 200, data: [
      {'id': 'c1', 'nome': 'Helena Prado', 'relacao': 'PSICOLOGO', 'whatsapp': '+5511999990000', 'prioridade': 0},
    ]))));
    await tester.pumpWidget(ProviderScope(
      overrides: [trustedContactsRepositoryProvider.overrideWithValue(TrustedContactsRepository(dio))],
      child: MaterialApp(home: ProfessionalDetailScreen(profissional: _profissional(tags: ['Psicólogo'], telefone: '+5511999990000'))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Já está na sua rede de apoio'), findsOneWidget);
  });
}
