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
}
