import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/features/calming_games/calming_games_section.dart';
import 'package:sincro_mobile/features/calming_games/estrada_tranquila_screen.dart';
import 'package:sincro_mobile/features/calming_games/voo_sereno_screen.dart';
import 'package:sincro_mobile/features/grounding_cards/grounding_cards_library_screen.dart';
import 'package:sincro_mobile/features/grounding_cards/grounding_cards_providers.dart';

Widget _wrap(Widget child, {ThemeData? theme}) {
  return MaterialApp(
    theme: theme ?? sincroLightTheme,
    home: Scaffold(body: ListView(children: [child])),
  );
}

void main() {
  testWidgets('renders both game cards without overflow at 360x640', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const CalmingGamesSection()));

    expect(find.text('Jogos para acalmar'), findsOneWidget);
    expect(find.text('Voo Sereno'), findsOneWidget);
    expect(find.text('Estrada Tranquila'), findsOneWidget);
    expect(find.text('~3 min · sem placar'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping Voo Sereno pushes VooSerenoScreen', (tester) async {
    await tester.pumpWidget(_wrap(const CalmingGamesSection()));
    await tester.tap(find.text('Voo Sereno'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(VooSerenoScreen), findsOneWidget);
    // Sem placar: nenhum número de pontos na tela.
    expect(find.textContaining('pontos'), findsNothing);
  });

  testWidgets('tapping Estrada Tranquila pushes EstradaTranquilaScreen', (tester) async {
    await tester.pumpWidget(_wrap(const CalmingGamesSection()));
    await tester.tap(find.text('Estrada Tranquila'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(EstradaTranquilaScreen), findsOneWidget);
  });

  testWidgets('library screen still shows the games when the cards API fails', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          groundingCardsProvider.overrideWith((ref, categoria) async => throw Exception('offline')),
          groundingCardFavoritosProvider.overrideWith((ref) async => throw Exception('offline')),
        ],
        child: const MaterialApp(home: GroundingCardsLibraryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Não foi possível carregar agora.'), findsOneWidget);
    expect(find.text('Jogos para acalmar'), findsOneWidget);
  });

  testWidgets('library screen shows the games above the cards list', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          groundingCardsProvider.overrideWith((ref, categoria) async => []),
          groundingCardFavoritosProvider.overrideWith((ref) async => []),
        ],
        child: const MaterialApp(home: GroundingCardsLibraryScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Jogos para acalmar'), findsOneWidget);
    expect(find.text('Nenhum cartão encontrado por aqui ainda.'), findsOneWidget);
  });
}
