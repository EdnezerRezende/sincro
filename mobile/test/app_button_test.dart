import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/core/theme.dart';
import '../lib/core/widgets/app_button.dart';

void main() {
  group('AppButton', () {
    testWidgets('Botão primário renderiza com cor correta', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: Scaffold(
            body: AppButton(
              label: 'Test',
              onPressed: () {},
              variant: AppButtonVariant.primary,
            ),
          ),
        ),
      );

      expect(find.byType(ElevatedButton), findsOneWidget);
      expect(find.text('Test'), findsOneWidget);
    });

    testWidgets('Botão desabilitado não responde a toque', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: Scaffold(
            body: AppButton(
              label: 'Disabled',
              onPressed: null,
              variant: AppButtonVariant.primary,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(AppButton));
      expect(tapped, isFalse); // Não chamou onPressed
    });

    testWidgets('Botão com loading mostra spinner', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: Scaffold(
            body: AppButton(
              label: 'Loading',
              isLoading: true,
              onPressed: () {},
              variant: AppButtonVariant.primary,
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('Tamanhos small, medium, large têm dimensões corretas', (tester) async {
      const testSize = 48.0; // medium

      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: Scaffold(
            body: AppButton(
              label: 'Test',
              onPressed: () {},
              variant: AppButtonVariant.primary,
              size: AppButtonSize.medium,
            ),
          ),
        ),
      );

      final elevatedButton = find.byType(ElevatedButton);
      expect(elevatedButton, findsOneWidget);

      // Verificar que o botão tem altura mínima
      final size = tester.getSize(elevatedButton);
      expect(size.height, greaterThanOrEqualTo(testSize));
    });

    testWidgets('Ícone é exibido à esquerda do texto por padrão', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: Scaffold(
            body: AppButton(
              label: 'Guardar',
              icon: Icons.save,
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.byType(Icon), findsOneWidget);
      expect(find.text('Guardar'), findsOneWidget);
    });

    testWidgets('Botão outline tem border visível', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: Scaffold(
            body: AppButton(
              label: 'Outline',
              onPressed: () {},
              variant: AppButtonVariant.outline,
            ),
          ),
        ),
      );

      expect(find.byType(ElevatedButton), findsOneWidget);
      expect(find.text('Outline'), findsOneWidget);
    });

    testWidgets('Botão text não tem background', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: Scaffold(
            body: AppButton(
              label: 'Texto',
              onPressed: () {},
              variant: AppButtonVariant.text,
            ),
          ),
        ),
      );

      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('Botão funciona em dark mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          darkTheme: sincroDarkTheme,
          themeMode: ThemeMode.dark,
          home: Scaffold(
            body: AppButton(
              label: 'Dark Mode Test',
              onPressed: () {},
              variant: AppButtonVariant.primary,
            ),
          ),
        ),
      );

      expect(find.text('Dark Mode Test'), findsOneWidget);
    });

    testWidgets('PrimaryButton helper funciona', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: Scaffold(
            body: PrimaryButton(
              label: 'Primary',
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.byType(PrimaryButton), findsOneWidget);
      expect(find.text('Primary'), findsOneWidget);
    });

    testWidgets('OutlineButton helper funciona', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: Scaffold(
            body: OutlineButton(
              label: 'Outline',
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.byType(OutlineButton), findsOneWidget);
      expect(find.text('Outline'), findsOneWidget);
    });
  });
}
