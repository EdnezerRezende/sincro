import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/section_row.dart';
import '../calming_games/calming_games_section.dart';
import 'grounding_card.dart';
import 'grounding_card_detail_screen.dart';
import 'grounding_cards_providers.dart';

/// Ícone do tile tonal por categoria de cartão (prancha "Alívio sensorial" da direção A).
IconData _iconeCategoria(String categoria) {
  switch (categoria) {
    case 'RESPIRACAO':
      return Icons.air;
    case 'ATERRAMENTO_SENSORIAL':
      return Icons.touch_app_outlined;
    case 'MOVIMENTO':
      return Icons.directions_walk_outlined;
    case 'ATENCAO_PLENA':
      return Icons.self_improvement_outlined;
    default:
      return Icons.auto_awesome_outlined;
  }
}

class GroundingCardsLibraryScreen extends ConsumerStatefulWidget {
  const GroundingCardsLibraryScreen({super.key});

  @override
  ConsumerState<GroundingCardsLibraryScreen> createState() => _GroundingCardsLibraryScreenState();
}

class _GroundingCardsLibraryScreenState extends ConsumerState<GroundingCardsLibraryScreen> {
  String? _categoriaSelecionada;

  Future<void> _abrirCard(GroundingCard card, Set<String> favoritosIds) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroundingCardDetailScreen(
          card: card,
          favoritadoInicial: favoritosIds.contains(card.id),
        ),
      ),
    );
    ref.invalidate(groundingCardFavoritosProvider);
  }

  SectionRow _linhaCard(GroundingCard card, Set<String> favoritosIds) {
    final favoritado = favoritosIds.contains(card.id);
    return SectionRow(
      icon: _iconeCategoria(card.categoria),
      title: card.titulo,
      subtitle: rotuloCategoria(card.categoria),
      trailing: favoritado
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.favorite, size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ],
            )
          : null,
      onTap: () => _abrirCard(card, favoritosIds),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardsAsync = ref.watch(groundingCardsProvider(_categoriaSelecionada));
    final favoritosAsync = ref.watch(groundingCardFavoritosProvider);
    final favoritosIds = favoritosAsync.maybeWhen(
      data: (favoritos) => favoritos.map((c) => c.id).toSet(),
      orElse: () => const <String>{},
    );
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Alívio sensorial')),
      body: cardsAsync.when(
        data: (cards) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              const CalmingGamesSection(),
              const SizedBox(height: 16),
              favoritosAsync.maybeWhen(
                data: (favoritos) => favoritos.isEmpty
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: SectionCard(
                          title: 'Favoritos',
                          children: [for (final card in favoritos) _linhaCard(card, favoritosIds)],
                        ),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
              Text(
                'Todos os cartões',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Todas'),
                    selected: _categoriaSelecionada == null,
                    onSelected: (_) => setState(() => _categoriaSelecionada = null),
                  ),
                  ...categoriasCartao.map((categoria) {
                    return ChoiceChip(
                      label: Text(rotuloCategoria(categoria)),
                      selected: _categoriaSelecionada == categoria,
                      onSelected: (_) => setState(() => _categoriaSelecionada = categoria),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 12),
              if (cards.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'Nenhum cartão encontrado por aqui ainda.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                )
              else
                SectionCard(children: [for (final card in cards) _linhaCard(card, favoritosIds)]),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            const CalmingGamesSection(),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Não foi possível carregar agora.', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => ref.invalidate(groundingCardsProvider(_categoriaSelecionada)),
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
