import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/biofeedback/escolher_card_sugerido.dart';
import 'package:sincro_mobile/features/grounding_cards/grounding_card.dart';

GroundingCard _card(String id) => GroundingCard(
      id: id,
      titulo: 'Card $id',
      categoria: 'RESPIRACAO',
      conteudo: 'Conteúdo',
      ativo: true,
    );

void main() {
  test('chooses among favoritos when non-empty, ignoring the other two lists', () {
    final resultado = escolherCardSugerido(
      favoritos: [_card('fav-1'), _card('fav-2')],
      respiracaoAtivos: [_card('resp-1')],
      todosAtivos: [_card('todos-1')],
      sortear: (max) => 1,
    );

    expect(resultado, 'fav-2');
  });

  test('falls back to respiracaoAtivos when favoritos is empty', () {
    final resultado = escolherCardSugerido(
      favoritos: [],
      respiracaoAtivos: [_card('resp-1'), _card('resp-2')],
      todosAtivos: [_card('todos-1')],
      sortear: (max) => 0,
    );

    expect(resultado, 'resp-1');
  });

  test('falls back to todosAtivos when favoritos and respiracaoAtivos are both empty', () {
    final resultado = escolherCardSugerido(
      favoritos: [],
      respiracaoAtivos: [],
      todosAtivos: [_card('todos-1'), _card('todos-2')],
      sortear: (max) => 1,
    );

    expect(resultado, 'todos-2');
  });

  test('returns null when all three lists are empty', () {
    final resultado = escolherCardSugerido(
      favoritos: [],
      respiracaoAtivos: [],
      todosAtivos: [],
      sortear: (max) => 0,
    );

    expect(resultado, isNull);
  });

  test('sortear receives the length of the list it is choosing from', () {
    final tamanhosRecebidos = <int>[];
    escolherCardSugerido(
      favoritos: [],
      respiracaoAtivos: [_card('a'), _card('b'), _card('c')],
      todosAtivos: [],
      sortear: (max) {
        tamanhosRecebidos.add(max);
        return 0;
      },
    );

    expect(tamanhosRecebidos, [3]);
  });
}
