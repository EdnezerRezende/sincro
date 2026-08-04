import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'biofeedback_background_task.dart';
import 'biofeedback_cache.dart';
import 'biofeedback_health_service.dart';
import 'biofeedback_summary.dart';
import 'biofeedback_summary_calculator.dart';
import 'biofeedback_sync_service.dart';

final biofeedbackHealthServiceProvider = Provider<BiofeedbackHealthService>((ref) {
  return BiofeedbackHealthService();
});

final biofeedbackCacheProvider = Provider<BiofeedbackCache>((ref) {
  return BiofeedbackCache();
});

final biofeedbackSyncServiceProvider = Provider<BiofeedbackSyncService>((ref) {
  return BiofeedbackSyncService(
    ref.watch(biofeedbackHealthServiceProvider),
    ref.watch(biofeedbackCacheProvider),
    BiofeedbackSummaryCalculator(),
  );
});

final biofeedbackBackgroundTaskProvider = Provider<BiofeedbackBackgroundTask>((ref) {
  return BiofeedbackBackgroundTask();
});

final biofeedbackAtivoProvider = FutureProvider.autoDispose<bool>((ref) {
  return ref.watch(biofeedbackCacheProvider).isAtivo();
});

final biofeedbackResumoProvider = FutureProvider.autoDispose<BiofeedbackSummary?>((ref) {
  return ref.watch(biofeedbackCacheProvider).getResumo();
});
