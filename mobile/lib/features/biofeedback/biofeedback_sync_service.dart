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
    await _garantirPermissoesAtualizadas();

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

  /// Pede as permissões que faltam para quem já usava o Biofeedback antes desta fase.
  ///
  /// `solicitarPermissao()` só roda na ativação, e quem ativou na Fase 1 já tem
  /// `biofeedback_ativo = true` — ou seja, nunca mais passaria por lá. Como a Fase 2 acrescentou
  /// PASSOS e TREINO ao conjunto pedido, esses usuários ficariam sem essas duas permissões, e a
  /// falha é silenciosa: o plugin `health` devolve lista vazia para um tipo não autorizado, então
  /// toda leitura pareceria "em repouso" e o dia inteiro (inclusive exercício) entraria na média
  /// que a linha de base usa — exatamente o que o filtro de atividade existe para evitar.
  ///
  /// Roda antes de qualquer leitura de saúde e vale tanto para a sincronização em primeiro plano
  /// quanto para a periódica em background, que é por onde a maioria dos usuários existentes
  /// passa primeiro depois da atualização.
  Future<void> _garantirPermissoesAtualizadas() async {
    if (!await _cache.isAtivo()) return;
    if (await _cache.getPermissoesVersao() >= BiofeedbackCache.versaoPermissoesAtual) return;

    try {
      await _healthService.solicitarPermissao();
    } catch (_) {
      // Best-effort, como o resto desta sincronização: uma falha ao pedir permissão não pode
      // impedir que os dados já autorizados sejam lidos e o resumo atualizado.
    }
    // Gravamos a versão independentemente do resultado (concedido, negado ou erro): insistir a
    // cada ciclo transformaria uma recusa deliberada em um pedido recorrente. Quem quiser
    // conceder depois ainda pode fazê-lo pelas configurações do app de saúde.
    await _cache.setPermissoesVersao(BiofeedbackCache.versaoPermissoesAtual);
  }
}
