import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/professionals/admin_professional_form_validation.dart';

void main() {
  group('parseTags', () {
    test('splits, trims, and drops empty entries', () {
      expect(parseTags(' TEA, TDAH ,, Ansiedade'), ['TEA', 'TDAH', 'Ansiedade']);
    });
  });

  group('parseCoordenada', () {
    test('parses a value within range', () {
      expect(parseCoordenada('-23.5', min: -90, max: 90, campo: 'Latitude'), -23.5);
    });

    test('throws for a value outside range', () {
      expect(
        () => parseCoordenada('200', min: -90, max: 90, campo: 'Latitude'),
        throwsA(isA<ProfessionalFormValidationException>()),
      );
    });

    test('throws for a non-numeric value', () {
      expect(
        () => parseCoordenada('abc', min: -180, max: 180, campo: 'Longitude'),
        throwsA(isA<ProfessionalFormValidationException>()),
      );
    });
  });

  group('validateTelefone', () {
    test('accepts a phone number with country code and 10-15 digits', () {
      expect(() => validateTelefone('+5511999999999'), returnsNormally);
    });

    test('throws when missing the leading plus', () {
      expect(
        () => validateTelefone('5511999999999'),
        throwsA(isA<ProfessionalFormValidationException>()),
      );
    });

    test('throws when there are fewer than 10 digits', () {
      expect(
        () => validateTelefone('+551199'),
        throwsA(isA<ProfessionalFormValidationException>()),
      );
    });

    test('throws for an empty value', () {
      expect(
        () => validateTelefone(''),
        throwsA(isA<ProfessionalFormValidationException>()),
      );
    });
  });

  group('validateBio', () {
    test('accepts a non-empty bio within 500 characters', () {
      expect(() => validateBio('Especialista em TEA e TDAH.'), returnsNormally);
    });

    test('throws for an empty bio', () {
      expect(() => validateBio('   '), throwsA(isA<ProfessionalFormValidationException>()));
    });

    test('throws for a bio longer than 500 characters', () {
      expect(
        () => validateBio('a' * 501),
        throwsA(isA<ProfessionalFormValidationException>()),
      );
    });
  });

  group('validateTags', () {
    test('accepts a non-empty tag list', () {
      expect(() => validateTags(['TEA']), returnsNormally);
    });

    test('throws for an empty tag list', () {
      expect(() => validateTags([]), throwsA(isA<ProfessionalFormValidationException>()));
    });
  });
}
