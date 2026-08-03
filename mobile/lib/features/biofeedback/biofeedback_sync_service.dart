import 'biofeedback_cache.dart';
import 'biofeedback_health_service.dart';
import 'biofeedback_summary_calculator.dart';

class BiofeedbackSyncService {
  BiofeedbackSyncService(this._healthService, this._cache, this._calculator);

  final BiofeedbackHealthService _healthService;
  final BiofeedbackCache _cache;
  final BiofeedbackSummaryCalculator _calculator;

  Future<void> sincronizar({DateTime? agora}) async {
    final leiturasFc = await _healthService.lerFrequenciaCardiacaHoje();
    final leiturasVfc = await _healthService.lerVariabilidadeHoje();
    final resumo = _calculator.calcular(
      leiturasFc: leiturasFc,
      leiturasVfc: leiturasVfc,
      agora: agora ?? DateTime.now(),
    );
    await _cache.setResumo(resumo);
  }
}
