import 'package:workmanager/workmanager.dart';
import 'biofeedback_cache.dart';
import 'biofeedback_health_service.dart';
import 'biofeedback_summary_calculator.dart';
import 'biofeedback_sync_service.dart';

const biofeedbackTaskName = 'biofeedback-sync';

/// Roda em um isolate separado do app principal — não tem acesso ao ProviderScope do Riverpod,
/// então monta suas próprias instâncias das mesmas classes usadas em primeiro plano.
@pragma('vm:entry-point')
void biofeedbackCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != biofeedbackTaskName) return true;
    final syncService = BiofeedbackSyncService(
      BiofeedbackHealthService(),
      BiofeedbackCache(),
      BiofeedbackSummaryCalculator(),
    );
    try {
      await syncService.sincronizar();
    } catch (_) {
      // Sincronização em background é best-effort: uma falha aqui não deve impedir
      // que o workmanager continue agendando as próximas execuções.
    }
    return true;
  });
}

class BiofeedbackBackgroundTask {
  Future<void> registrar(Duration frequencia) async {
    // Cancela antes de registrar de novo: troca de frequência precisa substituir o
    // agendamento anterior, não empilhar um segundo em paralelo.
    await Workmanager().cancelByUniqueName(biofeedbackTaskName);
    await Workmanager().registerPeriodicTask(
      biofeedbackTaskName,
      biofeedbackTaskName,
      frequency: frequencia,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }

  Future<void> cancelar() async {
    await Workmanager().cancelByUniqueName(biofeedbackTaskName);
  }
}
