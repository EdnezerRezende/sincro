import 'biofeedback_cache.dart';
import 'biofeedback_health_service.dart';
import 'biofeedback_stress_detector.dart';
import 'biofeedback_summary.dart';
import 'biofeedback_summary_calculator.dart';

class BiofeedbackSyncService {
  BiofeedbackSyncService(this._healthService, this._cache, this._calculator, this._detector);

  final BiofeedbackHealthService _healthService;
  final BiofeedbackCache _cache;
  final BiofeedbackSummaryCalculator _calculator;
  final BiofeedbackStressDetector _detector;

  Future<void> sincronizar({DateTime? agora}) async {
    final agoraEfetivo = agora ?? DateTime.now();
    final leiturasFc = await _healthService.lerFrequenciaCardiacaHoje();
    final leiturasVfc = await _healthService.lerVariabilidadeHoje();
    final leiturasPassos = await _healthService.lerPassosHoje();
    final treinos = await _healthService.lerTreinosHoje();

    final resumoBase = _calculator.calcular(
      leiturasFc: leiturasFc,
      leiturasVfc: leiturasVfc,
      agora: agoraEfetivo,
    );

    final historicoAtual = await _cache.getHistoricoRepouso();
    final medias = _detector.mediasEmRepouso(
      leiturasFc: leiturasFc,
      leiturasVfc: leiturasVfc,
      leiturasPassos: leiturasPassos,
      treinos: treinos,
    );
    final estado = _detector.detectar(
      mediaFcRepousoHoje: medias.mediaFc,
      mediaVfcRepousoHoje: medias.mediaVfc,
      historico: historicoAtual,
      hoje: agoraEfetivo,
    );
    final historicoAtualizado = _detector.atualizarHistorico(
      historicoAtual: historicoAtual,
      hoje: agoraEfetivo,
      mediaFcRepousoHoje: medias.mediaFc,
      mediaVfcRepousoHoje: medias.mediaVfc,
    );

    await _cache.setResumo(
      BiofeedbackSummary(
        ultimaFc: resumoBase.ultimaFc,
        mediaFcHoje: resumoBase.mediaFcHoje,
        mediaVfcHoje: resumoBase.mediaVfcHoje,
        estadoEstresse: estado,
        atualizadoEm: resumoBase.atualizadoEm,
      ),
    );
    await _cache.setHistoricoRepouso(historicoAtualizado);
  }
}
