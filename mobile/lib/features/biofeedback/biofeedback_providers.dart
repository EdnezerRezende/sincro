import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'biofeedback_alert_service.dart';
import 'biofeedback_background_task.dart';
import 'biofeedback_cache.dart';
import 'biofeedback_health_service.dart';
import 'biofeedback_stress_detector.dart';
import 'biofeedback_summary.dart';
import 'biofeedback_summary_calculator.dart';
import 'biofeedback_sync_service.dart';
import '../onboarding/anamnese/anamnese_providers.dart' show sensoryProfileRepositoryProvider;

final biofeedbackHealthServiceProvider = Provider<BiofeedbackHealthService>((ref) {
  return BiofeedbackHealthService();
});

final biofeedbackCacheProvider = Provider<BiofeedbackCache>((ref) {
  return BiofeedbackCache();
});

final biofeedbackAlertServiceProvider = Provider<BiofeedbackAlertService>((ref) {
  return BiofeedbackAlertService(FlutterLocalNotificationsPlugin());
});

final biofeedbackSyncServiceProvider = Provider<BiofeedbackSyncService>((ref) {
  return BiofeedbackSyncService(
    ref.watch(biofeedbackHealthServiceProvider),
    ref.watch(biofeedbackCacheProvider),
    BiofeedbackSummaryCalculator(),
    BiofeedbackStressDetector(),
    ref.watch(biofeedbackAlertServiceProvider),
    ref.watch(sensoryProfileRepositoryProvider),
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

final biofeedbackDiasNoHistoricoProvider = FutureProvider.autoDispose<int>((ref) async {
  final historico = await ref.watch(biofeedbackCacheProvider).getHistoricoRepouso();
  final hoje = DateTime.now();
  return historico.where((d) => !(d.data.year == hoje.year && d.data.month == hoje.month && d.data.day == hoje.day)).length;
});

final biofeedbackAlertasAtivosProvider = FutureProvider.autoDispose<bool>((ref) {
  return ref.watch(biofeedbackCacheProvider).getAlertasAtivos();
});
