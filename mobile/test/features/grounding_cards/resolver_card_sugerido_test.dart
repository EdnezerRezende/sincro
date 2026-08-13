// mobile/test/features/grounding_cards/resolver_card_sugerido_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/grounding_cards/grounding_card.dart';
import 'package:sincro_mobile/features/grounding_cards/resolver_card_sugerido.dart';

GroundingCard _card(String id) => GroundingCard(
      id: id,
      titulo: 'Card $id',
      categoria: 'RESPIRACAO',
      conteudo: 'Conteúdo',
      ativo: true,
    );

void main() {
  test('returns the card whose id matches', () {
    final cards = [_card('a'), _card('b'), _card('c')];

    final resultado = resolverCardSugerido(cards: cards, id: 'b');

    expect(resultado?.id, 'b');
  });

  test('returns null when no card matches the id', () {
    final cards = [_card('a'), _card('b')];

    final resultado = resolverCardSugerido(cards: cards, id: 'z');

    expect(resultado, isNull);
  });

  test('returns null for an empty list', () {
    final resultado = resolverCardSugerido(cards: [], id: 'a');

    expect(resultado, isNull);
  });
}
