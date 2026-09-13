import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/financas/conta_financeira.dart';

void main() {
  group('ContaFinanceira.fromJson', () {
    test('parses saldoAtual (sent as a Decimal-string) into a double', () {
      final conta = ContaFinanceira.fromJson({
        'id': 'conta-1',
        'nome': 'Conta corrente',
        'tipo': 'CORRENTE',
        'saldoAtual': '1234.56',
        'cor': '#FF0000',
      });

      expect(conta.id, 'conta-1');
      expect(conta.nome, 'Conta corrente');
      expect(conta.tipo, TipoContaFinanceira.corrente);
      expect(conta.saldoAtual, 1234.56);
      expect(conta.cor, '#FF0000');
    });

    test('cor is null when absent', () {
      final conta = ContaFinanceira.fromJson({
        'id': 'conta-2',
        'nome': 'Carteira',
        'tipo': 'CARTEIRA',
        'saldoAtual': '0.00',
      });
      expect(conta.cor, isNull);
    });

    test('parses POUPANCA', () {
      final conta = ContaFinanceira.fromJson({
        'id': 'conta-3',
        'nome': 'Poupança',
        'tipo': 'POUPANCA',
        'saldoAtual': '500.00',
      });
      expect(conta.tipo, TipoContaFinanceira.poupanca);
    });
  });
}
