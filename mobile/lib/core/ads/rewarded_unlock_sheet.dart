import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ads_service.dart';

/// Bottom sheet exibido quando a cota gratuita acaba: oferece assistir um vídeo (anúncio
/// premiado) em troca de [beneficio] por [duracao]. Devolve `true` se a recompensa foi ganha.
///
/// A oferta é sempre opcional e clara ("Agora não" fecha sem penalidade), como exigem as
/// políticas do AdMob para anúncios premiados.
Future<bool> mostrarDesbloqueioPremiado(
  BuildContext context, {
  required String titulo,
  required String beneficio,
  required Duration duracao,
}) async {
  final ganhou = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (_) => _RewardedUnlockSheet(titulo: titulo, beneficio: beneficio, duracao: duracao),
  );
  return ganhou ?? false;
}

class _RewardedUnlockSheet extends ConsumerStatefulWidget {
  const _RewardedUnlockSheet({required this.titulo, required this.beneficio, required this.duracao});

  final String titulo;
  final String beneficio;
  final Duration duracao;

  @override
  ConsumerState<_RewardedUnlockSheet> createState() => _RewardedUnlockSheetState();
}

class _RewardedUnlockSheetState extends ConsumerState<_RewardedUnlockSheet> {
  bool _exibindo = false;

  Future<void> _assistir() async {
    setState(() => _exibindo = true);
    final ganhou = await ref.read(adsServiceProvider).showRewarded();
    if (!mounted) return;
    if (ganhou) {
      Navigator.pop(context, true);
      return;
    }
    setState(() => _exibindo = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('O vídeo não foi concluído. Tente de novo em instantes.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disponivel = ref.watch(adsServiceProvider).rewardedReady;
    final minutos = widget.duracao.inMinutes;
    final duracaoTexto = minutos >= 60 && minutos % 60 == 0 ? '${minutos ~/ 60} h' : '$minutos min';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.play_circle_outline, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(widget.titulo, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Assista a um vídeo curto e ganhe ${widget.beneficio} por $duracaoTexto.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: disponivel && !_exibindo ? _assistir : null,
              icon: _exibindo
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.ondemand_video),
              label: Text(disponivel ? 'Assistir vídeo' : 'Vídeo indisponível no momento'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _exibindo ? null : () => Navigator.pop(context, false),
              child: const Text('Agora não'),
            ),
          ],
        ),
      ),
    );
  }
}
