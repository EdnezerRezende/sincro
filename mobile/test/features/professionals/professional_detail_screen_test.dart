import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/professionals/professional_detail_screen.dart';

void main() {
  test('buildWhatsAppUrl strips all non-digit characters', () {
    expect(buildWhatsAppUrl('+55 (11) 99999-9999'), 'https://wa.me/5511999999999');
  });

  test('buildTelUrl keeps a leading plus but strips other formatting', () {
    expect(buildTelUrl('+55 (11) 99999-9999'), 'tel:+5511999999999');
  });
}
