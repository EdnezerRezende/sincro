import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_providers.dart';
import 'cartao_credito.dart';
import 'cartoes_repository.dart';
import 'conta_financeira.dart';
import 'contas_repository.dart';
import 'dia_recebimento_repository.dart';
import 'finance_summary.dart';
import 'finance_summary_repository.dart';
import 'lancamento_financeiro.dart';
import 'lancamentos_repository.dart';

final contasRepositoryProvider = Provider<ContasRepository>((ref) {
  return ContasRepository(ref.watch(apiClientProvider).dio);
});

final contasProvider = FutureProvider.autoDispose<List<ContaFinanceira>>((ref) {
  return ref.watch(contasRepositoryProvider).list();
});

final cartoesRepositoryProvider = Provider<CartoesRepository>((ref) {
  return CartoesRepository(ref.watch(apiClientProvider).dio);
});

final cartoesProvider = FutureProvider.autoDispose<List<CartaoCredito>>((ref) {
  return ref.watch(cartoesRepositoryProvider).list();
});

final lancamentosRepositoryProvider = Provider<LancamentosRepository>((ref) {
  return LancamentosRepository(ref.watch(apiClientProvider).dio);
});

final lancamentosPendentesProvider = FutureProvider.autoDispose<List<LancamentoFinanceiro>>((ref) {
  return ref.watch(lancamentosRepositoryProvider).list(status: 'PENDENTE_REVISAO');
});

final lancamentosDoMesProvider =
    FutureProvider.autoDispose.family<List<LancamentoFinanceiro>, String>((ref, mes) {
  return ref.watch(lancamentosRepositoryProvider).list(status: 'CONFIRMADO', mes: mes);
});

final financeSummaryRepositoryProvider = Provider<FinanceSummaryRepository>((ref) {
  return FinanceSummaryRepository(ref.watch(apiClientProvider).dio);
});

final financeSummaryProvider = FutureProvider.autoDispose<FinanceSummary>((ref) {
  return ref.watch(financeSummaryRepositoryProvider).getResumo();
});

final diaRecebimentoRepositoryProvider = Provider<DiaRecebimentoRepository>((ref) {
  return DiaRecebimentoRepository(ref.watch(apiClientProvider).dio);
});
