import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'biofeedback_alert_service.dart';
import 'biofeedback_cache.dart';
import 'biofeedback_health_service.dart';
import 'biofeedback_stress_detector.dart';
import 'biofeedback_summary_calculator.dart';
import 'biofeedback_sync_service.dart';
import '../../core/api_client.dart';
import '../../core/api_providers.dart' show apiBaseUrl;
import '../../firebase_options.dart';
import '../onboarding/anamnese/sensory_profile_repository.dart';

const biofeedbackTaskName = 'biofeedback-sync';

/// Roda em um isolate separado do app principal — não tem acesso ao ProviderScope do Riverpod,
/// então monta suas próprias instâncias das mesmas classes usadas em primeiro plano.
@pragma('vm:entry-point')
void biofeedbackCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != biofeedbackTaskName) return true;

    // O motor de sincronização (permissões, leitura do plugin health, gravação em cache) nunca
    // dependeu de Firebase e sempre funcionou neste isolate isolado do main(). O caminho de
    // alerta, novo nesta fase, depende de rede autenticada (Firebase) — e este isolate nunca
    // rodou main(), então Firebase.initializeApp() nunca foi chamado aqui. Isolamos essa
    // inicialização (e a montagem do Dio autenticado que depende dela) num try/catch próprio,
    // separado do try/catch de sincronizar() logo abaixo: se Firebase.initializeApp() falhar
    // neste isolate específico, a sincronização inteira (inclusive leituras que nada têm a ver
    // com alertas) não pode ser derrubada por isso. Na falha, caímos para um Dio sem token de
    // autenticação — SensoryProfileRepository.get() falhará (401/erro de rede), mas
    // BiofeedbackSyncService já trata essa falha como "não notificar" e segue o resto do ciclo.
    //
    // O timeout cobre o outro modo de falha desta chamada: além de lançar, `initializeApp()` pode
    // simplesmente pendurar neste isolate. Sem ele, o ciclo inteiro (permissões, leitura do health,
    // gravação em cache) — nada disso precisa de Firebase — ficaria bloqueado antes de começar.
    // Um TimeoutException cai no mesmo `catch (_)` e usa o mesmo fallback sem autenticação.
    Dio dio;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
            .timeout(const Duration(seconds: 10));
      }
      dio = ApiClient(baseUrl: apiBaseUrl, firebaseAuth: FirebaseAuth.instance).dio;
    } catch (_) {
      dio = Dio(BaseOptions(baseUrl: apiBaseUrl));
    }

    final syncService = BiofeedbackSyncService(
      BiofeedbackHealthService(),
      BiofeedbackCache(),
      BiofeedbackSummaryCalculator(),
      BiofeedbackStressDetector(),
      BiofeedbackAlertService(FlutterLocalNotificationsPlugin()),
      SensoryProfileRepository(dio),
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
