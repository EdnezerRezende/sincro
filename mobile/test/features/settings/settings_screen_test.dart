// Configurações na direção A: grupos em `SectionCard` com título 16 bold, linhas com ícone
// tonal e o valor atual de cada preferência como subtítulo; funciona nos temas claro e escuro.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/core/theme/theme_mode_preference.dart';
import 'package:sincro_mobile/core/widgets/section_card.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_providers.dart';
import 'package:sincro_mobile/features/email_triage/email_triage_providers.dart';
import 'package:sincro_mobile/features/email_triage/gmail_connection_repository.dart';
import 'package:sincro_mobile/features/home/home_design_style.dart';
import 'package:sincro_mobile/features/home/home_layout_mode.dart';
import 'package:sincro_mobile/features/home/home_layout_preference.dart';
import 'package:sincro_mobile/features/home/home_providers.dart';
import 'package:sincro_mobile/features/onboarding/onboarding_providers.dart';
import 'package:sincro_mobile/features/onboarding/onboarding_status.dart';
import 'package:sincro_mobile/features/settings/settings_screen.dart';
import 'package:sincro_mobile/features/trusted_contacts/trusted_contact.dart';
import 'package:sincro_mobile/features/trusted_contacts/trusted_contacts_providers.dart';

/// Evita SharedPreferences nos diálogos de escolha (que releem a preferência ao abrir).
class _FakeHomeLayoutPreference extends HomeLayoutPreference {
  @override
  Future<HomeLayoutMode> getModo() async => HomeLayoutMode.resumo;
  @override
  Future<HomeDesignStyle> getDesign() async => HomeDesignStyle.minimalista;
  @override
  Future<void> setModo(HomeLayoutMode modo) async {}
  @override
  Future<void> setDesign(HomeDesignStyle design) async {}
}

Future<void> _rolarAte(WidgetTester tester, Finder alvo) async {
  await tester.scrollUntilVisible(alvo, 200, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

List<Override> _overrides({bool biofeedbackAtivo = false, bool isAdmin = false}) => [
      homeLayoutPreferenceProvider.overrideWithValue(_FakeHomeLayoutPreference()),
      homeLayoutModeProvider.overrideWith((ref) async => HomeLayoutMode.resumo),
      homeDesignStyleProvider.overrideWith((ref) async => HomeDesignStyle.minimalista),
      themeModeProvider.overrideWith((ref) async => ThemeModePreference.light),
      biofeedbackAtivoProvider.overrideWith((ref) async => biofeedbackAtivo),
      biofeedbackAlertasAtivosProvider.overrideWith((ref) async => true),
      biofeedbackFrequenciaProvider.overrideWith((ref) async => 30),
      gmailConnectionStatusProvider.overrideWith(
        (ref) async => const GmailConnectionStatus(connected: true, gmailEmail: 'seu@email.com'),
      ),
      onboardingStatusProvider.overrideWith((ref) async => OnboardingStatus(
            userId: 'u1',
            nome: 'Ana',
            hasSensoryProfile: true,
            trustedContactCount: 3,
            isAdmin: isAdmin,
            diaRecebimento: 5,
          )),
      trustedContactsListProvider.overrideWith((ref) async => const [
            TrustedContact(id: 'a', nome: 'Helena', relacao: 'PSICOLOGO', whatsapp: '+5511999990001', prioridade: 0),
            TrustedContact(id: 'b', nome: 'Mãe', relacao: 'FAMILIAR', whatsapp: '+5511999990002', prioridade: 1),
            TrustedContact(id: 'c', nome: 'João', relacao: 'OUTRO', whatsapp: '+5511999990003', prioridade: 2),
          ]),
    ];

Future<void> _pump(WidgetTester tester, {required ThemeData theme, bool biofeedbackAtivo = false, bool isAdmin = false}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: _overrides(biofeedbackAtivo: biofeedbackAtivo, isAdmin: isAdmin),
    child: MaterialApp(theme: theme, home: const SettingsScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('agrupa as preferências em cartões e mostra o valor atual como subtítulo', (tester) async {
    await _pump(tester, theme: sincroLightTheme);

    expect(find.text('Perfil & Preferências'), findsOneWidget);
    expect(find.text('Conexões'), findsOneWidget);
    expect(find.byType(SectionCard), findsAtLeastNWidgets(2));

    // Valores atuais visíveis sem abrir o diálogo.
    expect(find.text('Resumo simples'), findsOneWidget);
    expect(find.text('Minimalista Refinado'), findsOneWidget);
    expect(find.text('Claro'), findsOneWidget);
    expect(find.text('3 contatos'), findsOneWidget);
    expect(find.text('Conectado como seu@email.com'), findsOneWidget);
    expect(find.text('Dia 5 de cada mês'), findsOneWidget);

    // Grupos de baixo: rolar até eles (a ListView só monta o que está visível).
    await _rolarAte(tester, find.text('Conta'));
    expect(find.text('Ajuda'), findsOneWidget);
    expect(find.text('Conta'), findsOneWidget);
    expect(find.text('Sair'), findsOneWidget);

    // Sem Biofeedback ativo e sem admin, esses grupos não aparecem.
    expect(find.text('Biofeedback'), findsNothing);
    expect(find.text('Administração'), findsNothing);
  });

  testWidgets('com Biofeedback ativo e admin, mostra os grupos extras com a frequência atual', (tester) async {
    await _pump(tester, theme: sincroLightTheme, biofeedbackAtivo: true, isAdmin: true);

    await _rolarAte(tester, find.text('Desativar Biofeedback'));
    expect(find.text('Biofeedback'), findsOneWidget);
    expect(find.text('A cada 30 minutos'), findsOneWidget);
    expect(find.text('Alertas de estresse'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);

    await _rolarAte(tester, find.text('Gerenciar profissionais (admin)'));
    expect(find.text('Administração'), findsOneWidget);
    expect(find.text('Gerenciar profissionais (admin)'), findsOneWidget);
  });

  testWidgets('renderiza sem exceção no tema escuro', (tester) async {
    await _pump(tester, theme: sincroDarkTheme, biofeedbackAtivo: true, isAdmin: true);
    expect(tester.takeException(), isNull);
    expect(find.text('Perfil & Preferências'), findsOneWidget);
    await _rolarAte(tester, find.text('Sair'));
    expect(tester.takeException(), isNull);
    expect(find.text('Sair'), findsOneWidget);
  });

  testWidgets('a linha "Layout da tela inicial" abre o diálogo de escolha', (tester) async {
    await _pump(tester, theme: sincroLightTheme);
    await tester.tap(find.text('Layout da tela inicial'));
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsOneWidget);
    expect(find.text('Abas (Hoje / Apoio)'), findsOneWidget);
  });
}
