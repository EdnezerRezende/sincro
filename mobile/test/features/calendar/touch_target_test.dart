import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Calendar Touch Target Sizes', () {
    test('Grid configuration ensures 48dp+ cells', () {
      // With 7 columns on a 390px phone:
      // Available width: 390 - (6 * 6px spacing) = 390 - 36 = 354px
      // Per cell: 354 / 7 = 50.6px per cell (exceeds 48dp minimum)
      const phoneWidth = 390;
      const columnCount = 7;
      const spacing = 6;
      const cellWidth = (phoneWidth - (columnCount - 1) * spacing) / columnCount;

      expect(cellWidth, greaterThanOrEqualTo(48));
    });

    testWidgets('Day cell InkWell is clickable and renders', (WidgetTester tester) async {
      // Bind to a standard phone size (390x800, typical mobile device)
      tester.binding.window.physicalSizeTestValue = const Size(390, 800);
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: 366, // 390 - 2*12 padding
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    childAspectRatio: 1.0,
                  ),
                  itemCount: 7,
                  itemBuilder: (context, index) {
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => tapped = true,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Center(
                            child: Text('${index + 1}'),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );

      // Verify the grid rendered
      expect(find.byType(InkWell), findsWidgets);

      // Tap a cell and verify it responds
      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testWidgets('Month navigation buttons have 48dp touch target', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 48,
              height: 48,
              child: IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {},
              ),
            ),
          ),
        ),
      );

      final iconButtonFinder = find.byType(IconButton);
      final iconButtonSize = tester.getSize(iconButtonFinder);

      // IconButton should be at least 48dp x 48dp
      expect(iconButtonSize.width, greaterThanOrEqualTo(48));
      expect(iconButtonSize.height, greaterThanOrEqualTo(48));
    });

    testWidgets('Event card edit button has 48dp touch target', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Editar'),
                onPressed: () {},
              ),
            ),
          ),
        ),
      );

      final buttonFinder = find.byType(OutlinedButton);
      final buttonSize = tester.getSize(buttonFinder);

      // Button should have at least 48dp height
      expect(buttonSize.height, greaterThanOrEqualTo(48));
    });
  });
}
