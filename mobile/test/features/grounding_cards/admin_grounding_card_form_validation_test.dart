import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/grounding_cards/admin_grounding_card_form_validation.dart';

void main() {
  group('validateTitulo', () {
    test('accepts a non-empty title within 100 characters', () {
      expect(() => validateTitulo('Respiração 4-7-8'), returnsNormally);
    });

    test('rejects an empty title', () {
      expect(() => validateTitulo('   '), throwsA(isA<GroundingCardFormValidationException>()));
    });

    test('rejects a title longer than 100 characters', () {
      expect(() => validateTitulo('a' * 101), throwsA(isA<GroundingCardFormValidationException>()));
    });
  });

  group('validateConteudo', () {
    test('accepts non-empty content within 2000 characters', () {
      expect(() => validateConteudo('Inspire por 4 segundos...'), returnsNormally);
    });

    test('rejects empty content', () {
      expect(() => validateConteudo(''), throwsA(isA<GroundingCardFormValidationException>()));
    });

    test('rejects content longer than 2000 characters', () {
      expect(() => validateConteudo('a' * 2001), throwsA(isA<GroundingCardFormValidationException>()));
    });
  });
}
