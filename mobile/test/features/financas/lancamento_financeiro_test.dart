import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/financas/lancamento_financeiro.dart';

void main() {
  group('LancamentoFinanceiro.fromJson', () {
    test('parses a fully-populated confirmed lançamento', () {
      final lancamento = LancamentoFinanceiro.fromJson({
        'id': 'lanc-1',
        'tipo': 'FATURA_CARTAO',
        'descricao': 'Sua fatura fechou',
        'instituicao': 'Nubank',
        'valor': '512.40',
        'dataVencimento': '2026-10-10T00:00:00.000Z',
        'dataCompetencia': '2026-10-10T00:00:00.000Z',
        'status': 'CONFIRMADO',
        'origem': 'EMAIL_PARSER',
        'isPago': false,
        'codigoBarras': null,
        'cartaoId': 'cartao-1',
        'contaId': null,
      });

      expect(lancamento.id, 'lanc-1');
      expect(lancamento.tipo, TipoLancamento.faturaCartao);
      expect(lancamento.descricao, 'Sua fatura fechou');
      expect(lancamento.instituicao, 'Nubank');
      expect(lancamento.valor, 512.40);
      expect(lancamento.dataVencimento, DateTime.utc(2026, 10, 10));
      expect(lancamento.status, StatusLancamento.confirmado);
      expect(lancamento.origem, OrigemLancamento.emailParser);
      expect(lancamento.isPago, false);
      expect(lancamento.cartaoId, 'cartao-1');
      expect(lancamento.contaId, isNull);
    });

    test('valor is null when the parser could not extract an amount', () {
      final lancamento = LancamentoFinanceiro.fromJson({
        'id': 'lanc-2',
        'tipo': 'DESPESA',
        'descricao': 'Conta de luz',
        'instituicao': 'Enel',
        'valor': null,
        'dataVencimento': '2026-09-15T00:00:00.000Z',
        'dataCompetencia': '2026-09-15T00:00:00.000Z',
        'status': 'PENDENTE_REVISAO',
        'origem': 'EMAIL_PARSER',
        'isPago': false,
        'codigoBarras': null,
        'cartaoId': null,
        'contaId': null,
      });

      expect(lancamento.valor, isNull);
      expect(lancamento.status, StatusLancamento.pendenteRevisao);
    });

    test('parses MANUAL origem and IGNORADO status', () {
      final lancamento = LancamentoFinanceiro.fromJson({
        'id': 'lanc-3',
        'tipo': 'RECEITA',
        'descricao': 'Freela',
        'instituicao': null,
        'valor': '800.00',
        'dataVencimento': '2026-09-05T00:00:00.000Z',
        'dataCompetencia': '2026-09-05T00:00:00.000Z',
        'status': 'IGNORADO',
        'origem': 'MANUAL',
        'isPago': false,
        'codigoBarras': null,
        'cartaoId': null,
        'contaId': null,
      });

      expect(lancamento.tipo, TipoLancamento.receita);
      expect(lancamento.status, StatusLancamento.ignorado);
      expect(lancamento.origem, OrigemLancamento.manual);
    });
  });
}
