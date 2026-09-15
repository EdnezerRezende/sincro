import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/widgets/stat_tile.dart';
import '../../core/widgets/tonal_panel.dart';
import 'biofeedback_providers.dart';
import 'biofeedback_summary.dart';
import 'estado_estresse.dart';


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
    ref.invalidate(biofeedbackResumoProvider);
    // O histórico de repouso também muda na sincronização e é o que alimenta o contador
    // "(N de 7 dias)" — sem invalidar aqui, ele ficaria preso no valor anterior.
    ref.invalidate(biofeedbackDiasNoHistoricoProvider);
    ref.invalidate(biofeedbackPermissaoProvider);
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
      ref.invalidate(biofeedbackResumoProvider);
      ref.invalidate(biofeedbackDiasNoHistoricoProvider);
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
    required this.diasNoHistoricoAsync,
  });

  final BiofeedbackSummary? resumo;
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

  /// Dias de histórico necessários para a linha de base ficar pronta (ver
  /// `BiofeedbackStressDetector`). O histórico em si guarda até 14 dias.
  static const _diasParaLinhaDeBase = 7;

  static String _rotuloEstadoEstresse(
    EstadoEstresse estado,
    int diasNoHistorico,
  ) {
    switch (estado) {
      case EstadoEstresse.calmo:
        return 'Estado atual: Calmo';
      case EstadoEstresse.elevado:
        return 'Estado atual: Elevado';
      case EstadoEstresse.coletandoDados:
        // O contador é limitado a 7 porque o histórico pode ter até 14 dias e ainda assim
        // continuar "coletando dados" por outro motivo (nenhuma leitura em repouso hoje) —
        // sem o limite, apareceria um "13 de 7 dias".
        final dias = min(diasNoHistorico, _diasParaLinhaDeBase);
        return 'Coletando dados ($dias de $_diasParaLinhaDeBase dias)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final atual = resumo;
    if (atual == null) {
      return const _EmptyState();
    }
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final rotulos = _rotulos(atual.atualizadoEm, DateTime.now());
    final stressColor = switch (atual.estadoEstresse) {
      EstadoEstresse.calmo => context.sincroColors.success,
      EstadoEstresse.elevado => context.sincroColors.caution,
      EstadoEstresse.coletandoDados => colorScheme.onSurfaceVariant,
    };
    final rotuloEstado = diasNoHistoricoAsync.when(
      data: (dias) => _rotuloEstadoEstresse(atual.estadoEstresse, dias),
      // Só "Coletando dados" usa a contagem de dias; para calmo/elevado o rótulo já está pronto
      // e esperar pelo histórico só faria a linha piscar "Carregando..." à toa.
      loading: () => atual.estadoEstresse == EstadoEstresse.coletandoDados
          ? 'Carregando...'
          : _rotuloEstadoEstresse(atual.estadoEstresse, 0),
      error: (_, __) => _rotuloEstadoEstresse(atual.estadoEstresse, 0),
    );
    final atualizado = 'Atualizado ${rotulos.prefixoAtualizacao}às '
        '${TimeOfDay.fromDateTime(atual.atualizadoEm).format(context)}';
    final fcLabel = 'Frequência cardíaca em repouso ${rotulos.sufixoMedia}';
    final vfcLabel = 'Variabilidade em repouso ${rotulos.sufixoMedia}';
    final fc = atual.mediaFcHoje != null ? '${atual.mediaFcHoje!.round()}' : '—';
    final vfc = atual.mediaVfcHoje != null ? '${atual.mediaVfcHoje!.round()}' : '—';

    // Prancha "Biofeedback" da direção A: dois tiles de estatística lado a lado e, abaixo, o
    // painel tonal com o estado atual e o horário da última atualização.
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        // IntrinsicHeight: dentro de uma ListView a Row recebe altura infinita, e `stretch` sem
        // um limite derrubava o layout inteiro (tela em branco). Com ela, os dois tiles ficam
        // com a altura do mais alto, como na prancha.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            Expanded(
              child: StatTile(
                label: fcLabel,
                value: fc,
                unit: atual.mediaFcHoje != null ? 'bpm' : null,
                semanticsLabel: '$fcLabel: ${atual.mediaFcHoje != null ? '$fc bpm' : 'sem dados'}',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatTile(
                label: vfcLabel,
                value: vfc,
                unit: atual.mediaVfcHoje != null ? 'ms' : null,
                semanticsLabel: '$vfcLabel: ${atual.mediaVfcHoje != null ? '$vfc ms' : 'sem dados'}',
              ),
            ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TonalPanel(
          child: Row(
            children: [
              Icon(
                switch (atual.estadoEstresse) {
                  EstadoEstresse.calmo => Icons.check_circle_outline,
                  EstadoEstresse.elevado => Icons.warning_amber_outlined,
                  EstadoEstresse.coletandoDados => Icons.hourglass_empty_outlined,
                },
                size: 24,
                color: stressColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rotuloEstado,
                      style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      atualizado,
                      style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
