import 'package:flutter/foundation.dart' show debugPrint;

import 'biofeedback_alert_decision.dart';
import 'biofeedback_alert_service.dart';
import 'biofeedback_cache.dart';
import 'biofeedback_health_service.dart';
import 'biofeedback_stress_detector.dart';
import 'biofeedback_summary.dart';
import 'biofeedback_summary_calculator.dart';
import 'dia_repouso.dart';
import 'health_reading.dart';
import 'serie_dia.dart';
import 'treino_intervalo.dart';
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

  /// Quantos dias para trás o histórico é preenchido a partir da plataforma de saúde: 13 dias
  /// anteriores + hoje = a janela de 14 entradas do histórico (um dia a mais seria descartado na
  /// sincronização seguinte e o contador da tela oscilaria). A linha de base fica pronta na
  /// primeira sincronização de quem já usa o relógio há uma semana, em vez de esperar 7 dias.
  static const diasDePreenchimento = 13;

  /// Quanto tempo para trás procurar a FC em repouso calculada pela plataforma. Ela é gravada uma
  /// vez por dia, em horário que varia; até a de hoje existir, o relógio mostra a de ontem — e é
  /// isso que o app deve mostrar também.
  static const _janelaRepousoNativo = Duration(hours: 48);

  Future<void> sincronizar({DateTime? agora}) async {
    await _garantirPermissoesAtualizadas();

    final agoraEfetivo = agora ?? DateTime.now();
    final hoje = BiofeedbackHealthService.hoje(agoraEfetivo);
    final resumoAnterior = await _cache.getResumo();
    final leiturasFc = await _healthService.lerFrequenciaCardiaca(hoje);
    final leiturasVfc = await _healthService.lerVariabilidade(hoje);
    final leiturasPassos = await _healthService.lerPassos(hoje);
    final treinos = await _healthService.lerTreinos(hoje);
    final repousoNativo = await _lerRepousoNativo(agoraEfetivo);

    final resumoBase = _calculator.calcular(
      leiturasFc: leiturasFc,
      leiturasVfc: leiturasVfc,
      agora: agoraEfetivo,
    );

    final historicoAtual = await _preencherHistorico(
      await _cache.getHistoricoRepouso(),
      agoraEfetivo,
    );
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
    final serie = SerieDia.agregar(
      dia: hoje.inicio,
      leituras: leiturasFc,
      emRepouso: (t) => _detector.emRepouso(
        timestamp: t,
        leiturasPassos: leiturasPassos,
        treinos: treinos,
      ),
    );

    await _cache.setResumo(
      BiofeedbackSummary(
        ultimaFc: resumoBase.ultimaFc,
        ultimaFcEm: resumoBase.ultimaFcEm,
        // Usa a mesma média filtrada por repouso que alimenta `estado` acima, não a média bruta
        // do dia inteiro (`resumoBase.mediaFcHoje`) — senão o número mostrado na tela de detalhe
        // inclui picos de exercício/movimento que o algoritmo de estresse já exclui, e o app
        // acaba exibindo um valor que não é o que decide "calmo"/"elevado".
        mediaFcHoje: medias.mediaFc,
        mediaVfcHoje: medias.mediaVfc,
        fcRepousoNativa: repousoNativo?.valor,
        fcRepousoNativaEm: repousoNativo?.timestamp,
        fcMinHoje: serie.minimo,
        fcMaxHoje: serie.maximo,
        // A linha de base que a tela mostra é a mesma que decidiu `estado`: calculada sobre o
        // histórico já com o preenchimento retroativo, mas ainda sem a entrada de hoje.
        linhaDeBase: _detector.linhaDeBase(historico: historicoAtual, hoje: agoraEfetivo),
        usaVfc: _detector.usaVfc(
          mediaVfcRepousoHoje: medias.mediaVfc,
          historico: historicoAtual,
          hoje: agoraEfetivo,
        ),
        estadoEstresse: estado,
        atualizadoEm: resumoBase.atualizadoEm,
      ),
    );
    await _cache.setHistoricoRepouso(historicoAtualizado);
    await _cache.setSerieDia(serie);

    await _notificarSeNecessario(
      estadoAnterior: resumoAnterior?.estadoEstresse,
      estadoNovo: estado,
    );
  }

  /// A FC em repouso da plataforma é um extra: se a permissão nova (v3) foi negada ou a leitura
  /// falhar, o resto da sincronização segue sem ela.
  Future<HealthReading?> _lerRepousoNativo(DateTime agora) async {
    try {
      return await _healthService.lerFrequenciaRepousoNativa(
        (inicio: agora.subtract(_janelaRepousoNativo), fim: agora),
      );
    } catch (e) {
      debugPrint('biofeedback: leitura da FC em repouso nativa falhou: $e');
      return null;
    }
  }

  /// Preenche os dias anteriores que faltam no histórico lendo os últimos [diasDePreenchimento]
  /// dias da plataforma de uma só vez.
  ///
  /// Antes, o histórico só ganhava um dia por sincronização diária — "Coletando dados (0 de 7
  /// dias)" ficava assim por uma semana mesmo com meses de leituras já no HealthKit / Health
  /// Connect. Roda no máximo uma vez por dia (dias sem leitura em repouso continuam faltando e
  /// são tentados de novo no dia seguinte, sem custo a cada ciclo de 30 min). Best-effort: uma
  /// falha na leitura em lote devolve o histórico como estava e a sincronização de hoje segue.
  Future<List<DiaRepouso>> _preencherHistorico(List<DiaRepouso> historico, DateTime agora) async {
    // Aritmética de calendário (`day - i`), nunca `Duration(days: i)`: num fuso com horário de
    // verão, subtrair 24 h atravessando a virada cai às 23:00 do dia anterior e todo o histórico
    // fica datado no dia errado.
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final diasFaltantes = [
      for (var i = 1; i <= diasDePreenchimento; i++)
        DateTime(agora.year, agora.month, agora.day - i),
    ].where((dia) => !historico.any((d) => _mesmoDia(d.data, dia))).toList();
    if (diasFaltantes.isEmpty) return historico;

    final ultimo = await _cache.getUltimoPreenchimento();
    if (ultimo != null && _mesmoDia(ultimo, agora)) return historico;

    final periodo = (
      inicio: DateTime(agora.year, agora.month, agora.day - diasDePreenchimento),
      fim: hoje,
    );
    final List<HealthReading> fc;
    final List<HealthReading> vfc;
    final List<HealthReading> passos;
    final List<TreinoIntervalo> treinos;
    try {
      fc = await _healthService.lerFrequenciaCardiaca(periodo);
      vfc = await _healthService.lerVariabilidade(periodo);
      passos = await _healthService.lerPassos(periodo);
      treinos = await _healthService.lerTreinos(periodo);
    } catch (e) {
      // Sem Sentry no mobile por enquanto (ver main.dart); o debugPrint deixa o rastro em
      // desenvolvimento para uma falha que, em produção, é exatamente o sintoma que este
      // preenchimento existe para curar.
      debugPrint('biofeedback: preenchimento retroativo falhou: $e');
      return historico;
    }

    var atualizado = historico;
    for (final dia in diasFaltantes) {
      final fimDoDia = DateTime(dia.year, dia.month, dia.day + 1);
      bool noDia(DateTime t) => !t.isBefore(dia) && t.isBefore(fimDoDia);
      // Passos e treinos com uma folga de 5 min de cada lado: a janela de atividade de uma leitura
      // no começo ou no fim do dia atravessa a meia-noite.
      const folga = Duration(minutes: 5);
      bool pertoDoDia(DateTime inicio, DateTime fim) =>
          !fim.isBefore(dia.subtract(folga)) && !inicio.isAfter(fimDoDia.add(folga));
      final medias = _detector.mediasEmRepouso(
        leiturasFc: fc.where((l) => noDia(l.timestamp)).toList(),
        leiturasVfc: vfc.where((l) => noDia(l.timestamp)).toList(),
        leiturasPassos: passos.where((p) => pertoDoDia(p.timestamp, p.fim)).toList(),
        treinos: treinos.where((t) => pertoDoDia(t.inicio, t.fim)).toList(),
      );
      if (medias.mediaFc == null) continue;
      atualizado = _detector.inserirDia(
        atualizado,
        DiaRepouso(
          data: dia,
          mediaFcRepouso: medias.mediaFc!,
          mediaVfcRepouso: medias.mediaVfc,
        ),
      );
    }
    await _cache.setUltimoPreenchimento(agora);
    return atualizado;
  }

  static bool _mesmoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

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
