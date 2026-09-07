import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import 'biofeedback_providers.dart';
import 'biofeedback_summary.dart';
import 'estado_estresse.dart';

const Color _kBorderLight = Color(0xFF9C9690); // 2.76:1 vs #FAF8F5
const Color _kBorderDark = Color(0xFF66605A); // 2.68:1 vs #1A1F23

class BiofeedbackScreen extends ConsumerWidget {
  const BiofeedbackScreen({super.key});

  Future<void> _sincronizar(WidgetRef ref) async {
    try {
      await ref.read(biofeedbackSyncServiceProvider).sincronizar();
    } catch (_) {
      // Sincronização sob demanda é best-effort: se falhar, ainda mostramos os dados em cache.
    }
    ref.invalidate(biofeedbackResumoProvider);
    // O histórico de repouso também muda na sincronização e é o que alimenta o contador
    // "(N de 7 dias)" — sem invalidar aqui, ele ficaria preso no valor anterior.
    ref.invalidate(biofeedbackDiasNoHistoricoProvider);
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
          onRefresh: () => _sincronizar(ref),
          child: _ErrorState(onRetry: () => _sincronizar(ref)),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Biofeedback')),
      body: RefreshIndicator(
        onRefresh: () => _sincronizar(ref),
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
          error: (_, __) => _ErrorState(onRetry: () => _sincronizar(ref)),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
                Icons.monitor_heart_outlined,
                size: 48,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Nenhum dado ainda. Conecte seu wearable ou conceda acesso ao Apple Health / '
                  'Google Fit.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
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
    final borderColor = theme.brightness == Brightness.light
        ? _kBorderLight
        : _kBorderDark;
    final rotulos = _rotulos(atual.atualizadoEm, DateTime.now());
    final stressColor = switch (atual.estadoEstresse) {
      EstadoEstresse.calmo => context.sincroColors.success,
      EstadoEstresse.elevado => context.sincroColors.caution,
      EstadoEstresse.coletandoDados => colorScheme.onSurfaceVariant,
    };
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: borderColor, width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Frequência cardíaca média ${rotulos.sufixoMedia}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        atual.mediaFcHoje != null
                            ? '${atual.mediaFcHoje!.round()} bpm'
                            : '—',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: borderColor, width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Variabilidade média ${rotulos.sufixoMedia}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        atual.mediaVfcHoje != null
                            ? '${atual.mediaVfcHoje!.round()} ms'
                            : '—',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              switch (atual.estadoEstresse) {
                EstadoEstresse.calmo => Icons.check_circle_outline,
                EstadoEstresse.elevado => Icons.warning_amber_outlined,
                EstadoEstresse.coletandoDados => Icons.hourglass_empty_outlined,
              },
              size: 18,
              color: stressColor,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                diasNoHistoricoAsync.when(
                  data: (dias) =>
                      _rotuloEstadoEstresse(atual.estadoEstresse, dias),
                  // Só "Coletando dados" usa a contagem de dias; para calmo/elevado o rótulo já
                  // está pronto e esperar pelo histórico só faria a linha piscar "Carregando..."
                  // à toa.
                  loading: () =>
                      atual.estadoEstresse == EstadoEstresse.coletandoDados
                      ? 'Carregando...'
                      : _rotuloEstadoEstresse(atual.estadoEstresse, 0),
                  error: (_, __) =>
                      _rotuloEstadoEstresse(atual.estadoEstresse, 0),
                ),
                style: theme.textTheme.bodyMedium?.copyWith(color: stressColor),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Atualizado ${rotulos.prefixoAtualizacao}às '
          '${TimeOfDay.fromDateTime(atual.atualizadoEm).format(context)}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
