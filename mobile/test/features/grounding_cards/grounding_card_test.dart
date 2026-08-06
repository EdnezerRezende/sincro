import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/grounding_cards/grounding_card.dart';

void main() {
  test('categoriasCartao matches the fixed backend enum', () {
    expect(categoriasCartao, ['RESPIRACAO', 'ATERRAMENTO_SENSORIAL', 'MOVIMENTO', 'ATENCAO_PLENA', 'OUTRO']);
  });

  group('rotuloCategoria', () {
    test('translates each known category to a human-readable label', () {
      expect(rotuloCategoria('RESPIRACAO'), 'Respiração');
      expect(rotuloCategoria('ATERRAMENTO_SENSORIAL'), 'Aterramento Sensorial');
      expect(rotuloCategoria('MOVIMENTO'), 'Movimento/Alongamento');
      expect(rotuloCategoria('ATENCAO_PLENA'), 'Atenção Plena');
      expect(rotuloCategoria('OUTRO'), 'Outro');
    });

    test('falls back to "Outro" for an unrecognized value', () {
      expect(rotuloCategoria('ALGO_NOVO'), 'Outro');
    });
  });

  test('GroundingCard.fromJson parses all fields', () {
    final card = GroundingCard.fromJson({
      'id': 'c1',
      'titulo': 'Respiração 4-7-8',
      'categoria': 'RESPIRACAO',
      'conteudo': 'Inspire por 4 segundos...',
      'ativo': true,
    });

    expect(card.id, 'c1');
    expect(card.titulo, 'Respiração 4-7-8');
    expect(card.categoria, 'RESPIRACAO');
    expect(card.conteudo, 'Inspire por 4 segundos...');
    expect(card.ativo, true);
  });
}
