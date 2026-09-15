// Rede de apoio na direção A: contatos num cartão agrupado, atalho para buscar profissional
// cadastrado e rodapé com três botões de 56 dp; funciona nos temas claro e escuro.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/core/widgets/section_card.dart';
import 'package:sincro_mobile/core/widgets/section_row.dart';
import 'package:sincro_mobile/features/trusted_contacts/trusted_contact.dart';
import 'package:sincro_mobile/features/trusted_contacts/trusted_contacts_providers.dart';
import 'package:sincro_mobile/features/trusted_contacts/trusted_contacts_screen.dart';

const _contatos = [
  TrustedContact(id: 'a', nome: 'Dra. Helena Prado', relacao: 'PSICOLOGO', whatsapp: '+5511999990001', prioridade: 0),
  TrustedContact(id: 'b', nome: 'Mãe', relacao: 'FAMILIAR', whatsapp: '+5511999990002', prioridade: 1),
  TrustedContact(id: 'c', nome: 'João', relacao: 'OUTRO', whatsapp: '+5511999990003', prioridade: 2),
];

Future<void> _pump(WidgetTester tester, {required List<TrustedContact> contatos, required ThemeData theme}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [trustedContactsListProvider.overrideWith((ref) async => contatos)],
    child: MaterialApp(theme: theme, home: const TrustedContactsScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  for (final theme in [sincroLightTheme, sincroDarkTheme]) {
    testWidgets('agrupa os contatos, oferece buscar profissional e três botões de 56 dp (${theme.brightness.name})', (tester) async {
      await _pump(tester, contatos: _contatos, theme: theme);
      expect(tester.takeException(), isNull);

      expect(find.byType(SectionCard), findsNWidgets(2));
      expect(find.byType(SectionRow), findsNWidgets(4));
      expect(find.text('Dra. Helena Prado'), findsOneWidget);
      expect(find.text('PSICOLOGO'), findsOneWidget);
      expect(find.text('Buscar profissional cadastrado'), findsOneWidget);
      expect(find.text('Pelo nome ou perto de você'), findsOneWidget);

      for (final rotulo in ['Adicionar contato', 'Continuar', 'Pular por enquanto']) {
        final rect = tester.getRect(find.ancestor(of: find.text(rotulo), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first);
        expect(rect.height, greaterThanOrEqualTo(56), reason: '$rotulo com ${rect.height} dp');
        expect(rect.width, closeTo(350, 1), reason: '$rotulo com ${rect.width} dp');
        expect(rect.bottom, lessThanOrEqualTo(844));
      }
    });
  }

  testWidgets('sem contatos, orienta a cadastrar e esconde "Continuar"', (tester) async {
    await _pump(tester, contatos: const [], theme: sincroLightTheme);
    expect(find.textContaining('Cadastre ao menos um contato'), findsOneWidget);
    expect(find.text('Continuar'), findsNothing);
    expect(find.text('Adicionar contato'), findsOneWidget);
    expect(find.text('Buscar profissional cadastrado'), findsOneWidget);
  });
}
