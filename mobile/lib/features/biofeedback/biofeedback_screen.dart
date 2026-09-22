import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/widgets/stat_tile.dart';
import '../../core/widgets/tonal_panel.dart';
import 'biofeedback_daily_chart.dart';
import 'biofeedback_providers.dart';
import 'biofeedback_stress_detector.dart';
import 'biofeedback_summary.dart';
import 'estado_estresse.dart';
import 'serie_dia.dart';

class BiofeedbackScreen extends ConsumerWidget {
  const BiofeedbackScreen({super.key});

  Future<void> _sincronizar(BuildContext context, WidgetRef ref) async {
    var falhou = false;
    try {
      await ref.read(biofeedbackSyncServiceProvider).sincronizar();
    } catch (_) {
      // Sincronização sob demanda é best-effort: se falhar, ainda mostramos os dados em cache —
      // mas a pessoa precisa saber que o "puxar para atualizar" não funcionou, em vez de a tela
      // simplesmente não mudar nada e parecer que não fez nada.
      falhou = true;
    }
    invalidarDadosDeBiofeedback(ref);
    if (falhou && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível sincronizar agora. Tente novamente.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumoAsync = ref.watch(biofeedbackResumoProvider);

    // Riverpod 3 emits AsyncLoading(hasError:true, isLoading:true) during automatic
    // retries — checking hasError alone (without !isLoading) shows the error panel on
    // the very first failure, rather than after ~38 s of retries.
    if (resumoAsync.hasError) {
      return Scaffold(
        appBar: AppBar(title: const Text('Biofeedback')),
        body: RefreshIndicator(
          onRefresh: () => _sincronizar(context, ref),
          child: _ErrorState(onRetry: () => _sincronizar(context, ref)),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Biofeedback')),
      body: RefreshIndicator(
        onRefresh: () => _sincronizar(context, ref),
        child: resumoAsync.when(
          data: (resumo) => _BiofeedbackContent(
            resumo: resumo,
            // Série ainda carregando ou com erro vale como "sem série": o gráfico aparece vazio
            // em vez de segurar a tela inteira.
            serie: ref
                .watch(biofeedbackSerieDiaProvider)
                .maybeWhen(data: (s) => s, orElse: () => null),
            diasNoHistoricoAsync: ref.watch(biofeedbackDiasNoHistoricoProvider),
          ),
          loading: () => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 200),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (_, __) => _ErrorState(onRetry: () => _sincronizar(context, ref)),
        ),
      ),
    );
  }
}

/// Invalida tudo que a sincronização grava: resumo, série do dia, histórico (contador de dias da
/// linha de base) e o estado da permissão. Usado pela tela, pelo estado vazio e pela Home.
void invalidarDadosDeBiofeedback(WidgetRef ref) {
  ref.invalidate(biofeedbackResumoProvider);
  ref.invalidate(biofeedbackSerieDiaProvider);
  ref.invalidate(biofeedbackDiasNoHistoricoProvider);
  ref.invalidate(biofeedbackPermissaoProvider);
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // ListView (em vez de Center) garante um descendente rolável: o RefreshIndicator que envolve
    // esta tela depende disso para reconhecer o gesto de puxar-para-atualizar.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Não foi possível carregar os dados de biofeedback.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: onRetry,
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  Future<void> _concederAcesso(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(biofeedbackHealthServiceProvider).solicitarPermissao();
    } catch (_) {
      // Best-effort: se o pedido falhar, o botão continua disponível para tentar de novo.
    }
    ref.invalidate(biofeedbackPermissaoProvider);
    if (context.mounted) {
      await ref.read(biofeedbackSyncServiceProvider).sincronizar().catchError((_) {});
      invalidarDadosDeBiofeedback(ref);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    // `null` (estado desconhecido, comum no iOS) é tratado como "sem dado ainda" — só `false`
    // (negado com confiança, típico do Android/Health Connect) muda a mensagem e mostra o botão.
    final semPermissao = ref
        .watch(biofeedbackPermissaoProvider)
        .maybeWhen(data: (permitido) => permitido == false, orElse: () => false);
    // ListView (em vez de Center) garante um descendente rolável: o RefreshIndicator que envolve
    // esta tela depende disso para reconhecer o gesto de puxar-para-atualizar.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                semPermissao ? Icons.lock_outline : Icons.monitor_heart_outlined,
                size: 48,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  semPermissao
                      ? 'Sem acesso aos dados de saúde. Toque abaixo para conceder permissão.'
                      : 'Nenhum dado ainda. Conecte seu wearable ou conceda acesso ao Apple '
                          'Health / Google Fit.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              if (semPermissao) ...[
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => _concederAcesso(context, ref),
                  child: const Text('Conceder acesso'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Rótulos temporais do resumo, derivados da data em que ele foi calculado.
typedef _RotulosDeData = ({String sufixoMedia, String prefixoAtualizacao});

class _BiofeedbackContent extends StatelessWidget {
  const _BiofeedbackContent({
    required this.resumo,
    required this.serie,
    required this.diasNoHistoricoAsync,
  });

  final BiofeedbackSummary? resumo;
  final SerieDia? serie;
  final AsyncValue<int> diasNoHistoricoAsync;

  static bool _mesmoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// O resumo em cache pode ser de outro dia (app reaberto depois da meia-noite, antes de a
  /// próxima sincronização rodar). Chamar essas médias de "hoje" e mostrar só o horário faria um
  /// dado velho parecer atual, então os rótulos são qualificados com o dia a que se referem.
  static _RotulosDeData _rotulos(DateTime atualizadoEm, DateTime agora) {
    if (_mesmoDia(atualizadoEm, agora)) {
      return (sufixoMedia: 'hoje', prefixoAtualizacao: '');
    }
    if (_mesmoDia(atualizadoEm, agora.subtract(const Duration(days: 1)))) {
      return (sufixoMedia: 'ontem', prefixoAtualizacao: 'ontem ');
    }
    final dia = atualizadoEm.day.toString().padLeft(2, '0');
    final mes = atualizadoEm.month.toString().padLeft(2, '0');
    return (sufixoMedia: 'em $dia/$mes', prefixoAtualizacao: 'em $dia/$mes ');
  }

  static String _hora(DateTime t) => DateFormat('HH:mm').format(t);

  /// "às 14:50" quando é do mesmo dia do resumo; senão "ontem às 23:10" / "em 18/09 às 23:10".
  static String _quando(DateTime t, DateTime agora) {
    final r = _rotulos(t, agora);
    return '${r.prefixoAtualizacao}às ${_hora(t)}';
  }

  @override
  Widget build(BuildContext context) {
    final atual = resumo;
    if (atual == null) {
      return const _EmptyState();
    }
    final theme = Theme.of(context);
    final agora = DateTime.now();
    final rotulos = _rotulos(atual.atualizadoEm, agora);
    final empilhar = MediaQuery.textScalerOf(context).scale(1) >= 1.5;

    // Quatro números que o relógio também mostra — a leitura atual, a FC em repouso que a própria
    // plataforma calcula, os extremos do dia e a variabilidade — cada um com o que o qualifica.
    final ultimaTile = StatTile(
      label: 'Última leitura',
      value: atual.ultimaFc != null ? '${atual.ultimaFc!.round()}' : '—',
      unit: atual.ultimaFc != null ? 'bpm' : null,
      caption: atual.ultimaFcEm != null ? _quando(atual.ultimaFcEm!, agora) : 'sem leitura',
      semanticsLabel: atual.ultimaFc != null
          ? 'Última leitura: ${atual.ultimaFc!.round()} bpm ${_quando(atual.ultimaFcEm ?? atual.atualizadoEm, agora)}'
          : 'Última leitura: sem dados',
    );
    final repousoNativo = atual.fcRepousoNativa;
    final repousoValor = repousoNativo ?? atual.mediaFcHoje;
    final repousoCaption = repousoNativo != null
        ? 'pelo relógio'
        : atual.mediaFcHoje != null
            ? 'média de ${rotulos.sufixoMedia}'
            : 'sem leitura em repouso';
    final repousoTile = StatTile(
      label: 'Em repouso',
      value: repousoValor != null ? '${repousoValor.round()}' : '—',
      unit: repousoValor != null ? 'bpm' : null,
      caption: repousoCaption,
      semanticsLabel: repousoValor != null
          ? 'Em repouso: ${repousoValor.round()} bpm, $repousoCaption'
          : 'Em repouso: sem dados',
    );
    final temExtremos = atual.fcMinHoje != null && atual.fcMaxHoje != null;
    final extremosTile = StatTile(
      label: 'Mínima · Máxima',
      value: temExtremos ? '${atual.fcMinHoje!.round()}–${atual.fcMaxHoje!.round()}' : '—',
      unit: temExtremos ? 'bpm' : null,
      caption: rotulos.sufixoMedia,
      semanticsLabel: temExtremos
          ? 'Mínima ${atual.fcMinHoje!.round()} e máxima ${atual.fcMaxHoje!.round()} bpm ${rotulos.sufixoMedia}'
          : 'Mínima e máxima: sem dados',
    );
    final vfcTile = StatTile(
      label: 'Variabilidade',
      value: atual.mediaVfcHoje != null ? '${atual.mediaVfcHoje!.round()}' : '—',
      unit: atual.mediaVfcHoje != null ? 'ms' : null,
      caption: atual.mediaVfcHoje != null
          ? 'em repouso ${rotulos.sufixoMedia}'
          : 'relógio não enviou',
      semanticsLabel: atual.mediaVfcHoje != null
          ? 'Variabilidade em repouso ${rotulos.sufixoMedia}: ${atual.mediaVfcHoje!.round()} ms'
          : 'Variabilidade: o relógio não enviou',
    );

    // Série de outro dia (app aberto depois da meia-noite) é mostrada como do dia a que pertence;
    // sem série ainda, o gráfico aparece vazio para hoje.
    final serieExibida = serie ?? SerieDia(dia: DateTime(agora.year, agora.month, agora.day), pontos: const []);
    final rotuloSerie = _rotulos(serieExibida.dia, agora).sufixoMedia;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        // Tiles em pares com a mesma altura (IntrinsicHeight: dentro de uma ListView a Row recebe
        // altura infinita, e `stretch` sem limite derrubava o layout inteiro). A partir de ~1,5×
        // de texto os tiles empilham — em 137 dp os rótulos quebravam no meio da palavra.
        _ParDeTiles(esquerda: ultimaTile, direita: repousoTile, empilhar: empilhar),
        const SizedBox(height: 12),
        _ParDeTiles(esquerda: extremosTile, direita: vfcTile, empilhar: empilhar),
        const SizedBox(height: 12),
        _CartaoDoGrafico(
          titulo: 'Ao longo do dia · $rotuloSerie',
          serie: serieExibida,
          agora: agora,
          faixaRepouso: atual.faixaRepousoFc,
          fcRepouso: repousoNativo,
        ),
        const SizedBox(height: 12),
        _PainelDeEstado(
          resumo: atual,
          diasNoHistoricoAsync: diasNoHistoricoAsync,
          atualizado: 'Atualizado ${rotulos.prefixoAtualizacao}às ${_hora(atual.atualizadoEm)}',
        ),
        // Espaço extra no fim para o último cartão não colar na borda ao rolar.
        SizedBox(height: theme.textTheme.bodySmall?.fontSize ?? 12),
      ],
    );
  }
}

class _ParDeTiles extends StatelessWidget {
  const _ParDeTiles({required this.esquerda, required this.direita, required this.empilhar});

  final Widget esquerda;
  final Widget direita;
  final bool empilhar;

  @override
  Widget build(BuildContext context) {
    if (empilhar) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [esquerda, const SizedBox(height: 12), direita],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: esquerda),
          const SizedBox(width: 12),
          Expanded(child: direita),
        ],
      ),
    );
  }
}

class _CartaoDoGrafico extends StatelessWidget {
  const _CartaoDoGrafico({
    required this.titulo,
    required this.serie,
    required this.agora,
    required this.faixaRepouso,
    required this.fcRepouso,
  });

  final String titulo;
  final SerieDia serie;
  final DateTime agora;
  final ({double minimo, double maximo})? faixaRepouso;
  final double? fcRepouso;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Frequência cardíaca em blocos de 5 min. Toque no gráfico para ver um horário.',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            BiofeedbackDailyChart(
              serie: serie,
              agora: agora,
              faixaRepouso: faixaRepouso,
              fcRepouso: fcRepouso,
            ),
            const SizedBox(height: 8),
            _Legenda(temLinhaDeBase: faixaRepouso != null),
          ],
        ),
      ),
    );
  }
}

class _Legenda extends StatelessWidget {
  const _Legenda({required this.temLinhaDeBase});

  final bool temLinhaDeBase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final estilo = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    Widget item(Widget marca, String texto) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [marca, const SizedBox(width: 6), Text(texto, style: estilo)],
        );
    Widget ponto(Color cor) => Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
        );
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        item(ponto(scheme.primary), 'repouso'),
        item(ponto(scheme.onSurfaceVariant.withAlpha(140)), 'atividade'),
        if (temLinhaDeBase)
          item(
            Container(
              width: 14,
              height: 8,
              decoration: BoxDecoration(
                color: scheme.primary.withAlpha(40),
                border: Border.all(color: scheme.primary.withAlpha(90)),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            'sua linha de base',
          ),
      ],
    );
  }
}

class _PainelDeEstado extends StatelessWidget {
  const _PainelDeEstado({
    required this.resumo,
    required this.diasNoHistoricoAsync,
    required this.atualizado,
  });

  final BiofeedbackSummary resumo;
  final AsyncValue<int> diasNoHistoricoAsync;
  final String atualizado;

  /// Dias de histórico necessários para a linha de base ficar pronta (ver
  /// `BiofeedbackStressDetector`). O histórico em si guarda até 14 dias.
  static const _diasParaLinhaDeBase = BiofeedbackStressDetector.minDiasBaseline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final estado = resumo.estadoEstresse;
    final cor = switch (estado) {
      EstadoEstresse.calmo => context.sincroColors.success,
      EstadoEstresse.elevado => context.sincroColors.caution,
      EstadoEstresse.coletandoDados => scheme.onSurfaceVariant,
    };
    final icone = switch (estado) {
      EstadoEstresse.calmo => Icons.check_circle_outline,
      EstadoEstresse.elevado => Icons.warning_amber_outlined,
      EstadoEstresse.coletandoDados => Icons.hourglass_empty_outlined,
    };

    final String titulo;
    final String? explicacao;
    switch (estado) {
      case EstadoEstresse.calmo:
        titulo = 'Estado atual: Calmo';
        explicacao = resumo.usaVfc
            ? null
            : 'Detecção só pela frequência cardíaca: o relógio não enviou variabilidade (VFC).';
      case EstadoEstresse.elevado:
        titulo = 'Estado atual: Elevado';
        explicacao = resumo.usaVfc
            ? 'Frequência em repouso acima da sua linha de base e variabilidade abaixo dela.'
            : 'Frequência em repouso bem acima da sua linha de base (sem VFC do relógio).';
      case EstadoEstresse.coletandoDados:
        // Só até 7: o histórico pode ter 14 dias e ainda estar "coletando" por outro motivo
        // (nenhuma leitura em repouso hoje) — sem o limite, apareceria "13 de 7 dias".
        final int diasPrevios = resumo.linhaDeBase?.dias ??
            diasNoHistoricoAsync.maybeWhen<int>(data: (d) => d, orElse: () => 0);
        final dias = min(diasPrevios, _diasParaLinhaDeBase);
        titulo = 'Linha de base: $dias de $_diasParaLinhaDeBase dias';
        if (dias < _diasParaLinhaDeBase) {
          final faltam = _diasParaLinhaDeBase - dias;
          explicacao = 'Faltam $faltam ${faltam == 1 ? 'dia' : 'dias'} com leituras em repouso. '
              'O app já busca os últimos 14 dias no seu relógio; use-o também durante a noite.';
        } else {
          explicacao = 'Ainda sem leitura em repouso hoje. Fique alguns minutos parado com o '
              'relógio no pulso e puxe para atualizar.';
        }
    }

    return TonalPanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 24, color: cor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  atualizado,
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                if (explicacao != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    explicacao,
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
