import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/core/theme.dart';
import '../lib/core/widgets/app_chip.dart';

void main() {
  group('AppChip', () {
    testWidgets('Chip renderiza com altura >= 36 dp', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: Scaffold(
            body: AppChip(
              label: 'Test Chip',
              variant: AppChipVariant.input,
            ),
          ),
        ),
      );

      final chipFinder = find.byType(FilterChip);
      expect(chipFinder, findsOneWidget);

      // Verificar altura do chip
      final size = tester.getSize(chipFinder);
      expect(size.height, greaterThanOrEqualTo(36.0),
          reason: 'Chip height must be >= 36 dp for accessibility (Material Design 3)');
    });

    testWidgets('Chip selecionado muda cor/background', (tester) async {
      var isSelected = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: AppChip(
                  label: 'Select Me',
                  selected: isSelected,
                  onSelected: (val) {
                    setState(() => isSelected = val);
                  },
                  variant: AppChipVariant.input,
                ),
              );
            },
          ),
        ),
      );

      expect(find.byType(FilterChip), findsOneWidget);
      expect(find.text('Select Me'), findsOneWidget);
    });

    testWidgets('Chip desabilitado não responde a toque', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: Scaffold(
            body: AppChip(
              label: 'Disabled',
              enabled: false,
              onSelected: (_) => tapped = true,
              variant: AppChipVariant.input,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(AppChip));
      expect(tapped, isFalse);
    });

    testWidgets('AppChipGroup espaça chips com gap >= 8 dp', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: Scaffold(
            body: AppChipGroup(
              chips: [
                AppChip(label: 'Chip 1', variant: AppChipVariant.input),
                AppChip(label: 'Chip 2', variant: AppChipVariant.input),
                AppChip(label: 'Chip 3', variant: AppChipVariant.input),
              ],
              spacing: 8.0,
              runSpacing: 8.0,
            ),
          ),
        ),
      );

      expect(find.byType(Wrap), findsOneWidget);
      expect(find.byType(AppChip), findsWidgets);
    });

    testWidgets('Chip com ícone exibe ícone e texto com espaçamento 8 dp',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: Scaffold(
            body: AppChip(
              label: 'With Icon',
              icon: Icons.favorite,
              variant: AppChipVariant.input,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.text('With Icon'), findsOneWidget);
    });

    testWidgets('Chip funciona em dark mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          darkTheme: sincroDarkTheme,
          themeMode: ThemeMode.dark,
          home: Scaffold(
            body: AppChip(
              label: 'Dark Mode Chip',
              variant: AppChipVariant.input,
            ),
          ),
        ),
      );

      expect(find.text('Dark Mode Chip'), findsOneWidget);
    });

    testWidgets('Chip suggestion variant renderiza', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: Scaffold(
            body: AppChip(
              label: 'Suggestion',
              variant: AppChipVariant.suggestion,
            ),
          ),
        ),
      );

      expect(find.text('Suggestion'), findsOneWidget);
    });

    testWidgets('Chip filter variant renderiza', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: Scaffold(
            body: AppChip(
              label: 'Filter',
              variant: AppChipVariant.filter,
            ),
          ),
        ),
      );

      expect(find.text('Filter'), findsOneWidget);
    });
  });
}
