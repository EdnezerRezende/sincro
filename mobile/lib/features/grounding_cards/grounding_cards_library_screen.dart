import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'grounding_card.dart';
import 'grounding_card_detail_screen.dart';
import 'grounding_cards_providers.dart';

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

  @override
  Widget build(BuildContext context) {
    final cardsAsync = ref.watch(groundingCardsProvider(_categoriaSelecionada));
    final favoritosAsync = ref.watch(groundingCardFavoritosProvider);
    final favoritosIds = favoritosAsync.maybeWhen(
      data: (favoritos) => favoritos.map((c) => c.id).toSet(),
      orElse: () => const <String>{},
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Alívio sensorial')),
      body: cardsAsync.when(
        data: (cards) {
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              favoritosAsync.maybeWhen(
                data: (favoritos) => favoritos.isEmpty
                    ? const SizedBox.shrink()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('Favoritos', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          ...favoritos.map((card) => ListTile(
                                title: Text(card.titulo),
                                subtitle: Text(rotuloCategoria(card.categoria)),
                                trailing: const Icon(Icons.favorite, size: 18),
                                onTap: () => _abrirCard(card, favoritosIds),
                              )),
                          const Divider(),
                        ],
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Wrap(
                  spacing: 8,
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
              ),
              if (cards.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Nenhum cartão encontrado por aqui ainda.')),
                )
              else
                ...cards.map((card) => ListTile(
                      title: Text(card.titulo),
                      subtitle: Text(rotuloCategoria(card.categoria)),
                      trailing: favoritosIds.contains(card.id) ? const Icon(Icons.favorite, size: 18) : null,
                      onTap: () => _abrirCard(card, favoritosIds),
                    )),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Padding(
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
        ),
      ),
    );
  }
}
