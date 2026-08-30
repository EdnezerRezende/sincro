// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sincro_mobile/main.dart';

void main() {
  testWidgets('App initializes with login screen', (WidgetTester tester) async {
    // Build our app and trigger a frame. SincroApp reads providers, so it needs a
    // ProviderScope ancestor — same as the real bootstrap in main().
    await tester.pumpWidget(const ProviderScope(child: SincroApp()));

    // Verify that the login screen is displayed
    expect(find.text('Entrar'), findsWidgets);
  });
}
