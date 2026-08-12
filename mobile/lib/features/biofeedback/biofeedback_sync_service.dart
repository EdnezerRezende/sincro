import 'biofeedback_alert_decision.dart';
import 'biofeedback_alert_service.dart';
import 'biofeedback_cache.dart';
import 'biofeedback_health_service.dart';
import 'biofeedback_stress_detector.dart';
import 'biofeedback_summary.dart';
import 'biofeedback_summary_calculator.dart';
import 'escolher_card_sugerido.dart';
import 'estado_estresse.dart';
import '../grounding_cards/grounding_card.dart';
import '../grounding_cards/grounding_cards_repository.dart';
import '../onboarding/anamnese/sensory_profile_repository.dart';

class BiofeedbackSyncService {
  BiofeedbackSyncService(
    this._healthService,
    this._cache,
    this._calculator,
    this._detector,
    this._alertService,
    this._sensoryProfileRepository,
    this._groundingCardsRepository,
  );

  final BiofeedbackHealthService _healthService;
  final BiofeedbackCache _cache;
  final BiofeedbackSummaryCalculator _calculator;
  final BiofeedbackStressDetector _detector;
  final BiofeedbackAlertService _alertService;
  final SensoryProfileRepository _sensoryProfileRepository;
  final GroundingCardsRepository _groundingCardsRepository;

  Future<void> sincronizar({DateTime? agora}) async {
    await _garantirPermissoesAtualizadas();

    final agoraEfetivo = agora ?? DateTime.now();
    final resumoAnterior = await _cache.getResumo();
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

    await _notificarSeNecessario(
      estadoAnterior: resumoAnterior?.estadoEstresse,
      estadoNovo: estado,
    );
  }

  /// Só lê a rede (tolerância de notificação) quando as condições mais baratas já indicam uma
  /// transição real para "elevado" com os alertas ligados — evita uma chamada de rede a cada
  /// ciclo de sincronização quando não há nada para decidir.
  Future<void> _notificarSeNecessario({
    required EstadoEstresse? estadoAnterior,
    required EstadoEstresse estadoNovo,
  }) async {
    final transicaoRelevante =
        estadoAnterior != EstadoEstresse.elevado && estadoNovo == EstadoEstresse.elevado;
    if (!transicaoRelevante) return;

    final alertasAtivos = await _cache.getAlertasAtivos();
    if (!alertasAtivos) return;

    String? tolerancia;
    try {
      final dados = await _sensoryProfileRepository.get();
      tolerancia = dados?['toleranciaNotificacao'] as String?;
    } catch (_) {
      // Falha ao ler a preferência é tratada como "não notificar" (silencioso por padrão),
      // nunca como motivo para notificar mesmo sem saber a preferência do usuário.
      tolerancia = null;
    }

    if (!deveAlertar(
      estadoAnterior: estadoAnterior,
      estadoNovo: estadoNovo,
      alertasAtivos: alertasAtivos,
      tolerancia: tolerancia,
    )) {
      return;
    }

    final cardSugerido = await _buscarCardSugerido();
    await _alertService.mostrarAlerta(cardSugerido: cardSugerido);
  }

  /// Escolhe um grounding card para sugerir junto do alerta (favoritos > categoria Respiração >
  /// qualquer card ativo). Cada busca é best-effort — uma falha em qualquer uma delas vira lista
  /// vazia, nunca uma exceção que impediria o alerta em si de disparar.
  Future<GroundingCard?> _buscarCardSugerido() async {
    final favoritos = await _listaSeguraDeCards(_groundingCardsRepository.listFavoritos);
    final respiracaoAtivos = await _listaSeguraDeCards(
      () => _groundingCardsRepository.list(categoria: 'RESPIRACAO'),
    );
    final todosAtivos = await _listaSeguraDeCards(_groundingCardsRepository.list);

    final cardId = escolherCardSugerido(
      favoritos: favoritos,
      respiracaoAtivos: respiracaoAtivos,
      todosAtivos: todosAtivos,
      sortear: sortearIndiceAleatorio,
    );
    if (cardId == null) return null;

    return [...favoritos, ...respiracaoAtivos, ...todosAtivos]
        .firstWhere((card) => card.id == cardId);
  }

  Future<List<GroundingCard>> _listaSeguraDeCards(
    Future<List<GroundingCard>> Function() buscar,
  ) async {
    try {
      // Estas buscas rodam depois que deveAlertar() já decidiu disparar o alerta — um socket
      // pendurado aqui atrasaria ou derrubaria a notificação em si, então o timeout degrada para
      // o mesmo "trata como lista vazia" que uma exceção já recebe no catch abaixo.
      return await buscar().timeout(const Duration(seconds: 5));
    } catch (_) {
      return const [];
    }
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
