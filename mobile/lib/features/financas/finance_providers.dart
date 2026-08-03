import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_providers.dart';
import 'finance_connection.dart';
import 'finance_connection_repository.dart';
import 'finance_summary.dart';
import 'finance_summary_repository.dart';

final financeConnectionRepositoryProvider = Provider<FinanceConnectionRepository>((ref) {
  return FinanceConnectionRepository(ref.watch(apiClientProvider).dio);
});

final financeConnectionsProvider = FutureProvider.autoDispose<List<FinanceConnection>>((ref) {
  return ref.watch(financeConnectionRepositoryProvider).listConnections();
});

final financeSummaryRepositoryProvider = Provider<FinanceSummaryRepository>((ref) {
  return FinanceSummaryRepository(ref.watch(apiClientProvider).dio);
});

final financeSummaryProvider = FutureProvider.autoDispose<FinanceSummary>((ref) {
  return ref.watch(financeSummaryRepositoryProvider).getResumo();
});
