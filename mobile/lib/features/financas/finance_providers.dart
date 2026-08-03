import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_providers.dart';
import 'finance_connection.dart';
import 'finance_connection_repository.dart';

final financeConnectionRepositoryProvider = Provider<FinanceConnectionRepository>((ref) {
  return FinanceConnectionRepository(ref.watch(apiClientProvider).dio);
});

final financeConnectionsProvider = FutureProvider.autoDispose<List<FinanceConnection>>((ref) {
  return ref.watch(financeConnectionRepositoryProvider).listConnections();
});
