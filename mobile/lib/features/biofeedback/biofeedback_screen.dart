import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'biofeedback_providers.dart';
import 'biofeedback_summary.dart';
import 'estado_estresse.dart';

class BiofeedbackScreen extends ConsumerWidget {
  const BiofeedbackScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumoAsync = ref.watch(biofeedbackResumoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Biofeedback')),
      body: RefreshIndicator(
        onRefresh: () async {
          try {
            await ref.read(biofeedbackSyncServiceProvider).sincronizar();
          } catch (_) {
            // Sincronização sob demanda é best-effort: se falhar, ainda mostramos os dados em cache.
          }
          ref.invalidate(biofeedbackResumoProvider);
          // O histórico de repouso também muda na sincronização e é o que alimenta o contador
          // "(N de 7 dias)" — sem invalidar aqui, ele ficaria preso no valor anterior.
          ref.invalidate(biofeedbackDiasNoHistoricoProvider);
        },
        child: resumoAsync.when(
          data: (resumo) => _BiofeedbackContent(
            resumo: resumo,
            diasNoHistoricoAsync: ref.watch(biofeedbackDiasNoHistoricoProvider),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => ListView(
            children: const [
              Padding(
                padding: EdgeInsets.all(24),
                child: Text('Não foi possível carregar seus dados. Puxe para tentar novamente.'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rótulos temporais do resumo, derivados da data em que ele foi calculado.
typedef _RotulosDeData = ({String sufixoMedia, String prefixoAtualizacao});

class _BiofeedbackContent extends StatelessWidget {
  const _BiofeedbackContent({required this.resumo, required this.diasNoHistoricoAsync});

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

  static String _rotuloEstadoEstresse(EstadoEstresse estado, int diasNoHistorico) {
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
      return ListView(
        children: const [
          Padding(
            padding: EdgeInsets.all(24),
            child: Text('Nenhum dado disponível ainda. 🌿'),
          ),
        ],
      );
    }
    final rotulos = _rotulos(atual.atualizadoEm, DateTime.now());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Frequência cardíaca média ${rotulos.sufixoMedia}',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  atual.mediaFcHoje != null ? '${atual.mediaFcHoje!.round()} bpm' : '—',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Variabilidade média ${rotulos.sufixoMedia}',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  atual.mediaVfcHoje != null ? '${atual.mediaVfcHoje!.round()} ms' : '—',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          diasNoHistoricoAsync.when(
            data: (dias) => _rotuloEstadoEstresse(atual.estadoEstresse, dias),
            // Só "Coletando dados" usa a contagem de dias; para calmo/elevado o rótulo já está
            // pronto e esperar pelo histórico só faria a linha piscar "Carregando..." à toa.
            loading: () => atual.estadoEstresse == EstadoEstresse.coletandoDados
                ? 'Carregando...'
                : _rotuloEstadoEstresse(atual.estadoEstresse, 0),
            error: (_, __) => _rotuloEstadoEstresse(atual.estadoEstresse, 0),
          ),
          style: const TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 16),
        Text(
          'Atualizado ${rotulos.prefixoAtualizacao}às '
          '${TimeOfDay.fromDateTime(atual.atualizadoEm).format(context)}',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
}
