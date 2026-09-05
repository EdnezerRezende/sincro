import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_providers.dart';
import 'calendar_event.dart';
import 'calendar_repository.dart';

/// Provider que fornece a instância do repositório de calendário.
/// Conecta ao ApiClient do Riverpod central para usar a mesma instância Dio.
final calendarRepositoryProvider = Provider<CalendarRepository>((ref) {
  return CalendarRepository(ref.watch(apiClientProvider).dio);
});

/// Provider que lista eventos dos próximos 7 dias.
/// Auto-dispose para liberar a memória quando a tela sai do escopo.
/// Pode ser invalidado com `ref.invalidate(upcomingEventsProvider)` para forçar refresh.
final upcomingEventsProvider = FutureProvider.autoDispose<List<CalendarEvent>>((ref) {
  return ref.watch(calendarRepositoryProvider).listUpcomingEvents();
});

/// Provider que lista eventos de um mês específico.
/// Recebe ano e mês como parâmetros.
/// Usado pela visualização do calendário para destacar dias com eventos.
final monthEventsProvider = FutureProvider.autoDispose.family<List<CalendarEvent>, (int, int)>((ref, params) {
  final (ano, mes) = params;
  return ref.watch(calendarRepositoryProvider).listMonthEvents(ano, mes);
});
