import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/financas/cartao_credito.dart';

void main() {
  test('CartaoCredito.fromJson parses limiteTotal (Decimal-string) into a double', () {
    final cartao = CartaoCredito.fromJson({
      'id': 'cartao-1',
      'nome': 'Nubank',
      'diaFechamento': 5,
      'diaVencimento': 12,
      'limiteTotal': '3000.00',
      'cor': '#8A05BE',
    });

    expect(cartao.id, 'cartao-1');
    expect(cartao.nome, 'Nubank');
    expect(cartao.diaFechamento, 5);
    expect(cartao.diaVencimento, 12);
    expect(cartao.limiteTotal, 3000.0);
    expect(cartao.cor, '#8A05BE');
  });

  test('cor is null when absent', () {
    final cartao = CartaoCredito.fromJson({
      'id': 'cartao-2',
      'nome': 'Itaú',
      'diaFechamento': 1,
      'diaVencimento': 10,
      'limiteTotal': '1500.00',
    });
    expect(cartao.cor, isNull);
  });
}
