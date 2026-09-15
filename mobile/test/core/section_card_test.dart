import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/widgets/section_card.dart';

void main() {
  testWidgets('renders title, children and n-1 dividers', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SectionCard(title: 'Apoio', children: [Text('a'), Text('b'), Text('c')])),
    ));
    expect(find.text('Apoio'), findsOneWidget);
    expect(find.byType(Divider), findsNWidgets(2));
    expect(find.byType(Card), findsOneWidget);
  });
}
