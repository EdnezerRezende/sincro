import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'admin_grounding_card_form_screen.dart';
import 'grounding_card.dart';
import 'grounding_cards_providers.dart';

final adminGroundingCardsListProvider = FutureProvider.autoDispose<List<GroundingCard>>((ref) {
  return ref.watch(adminGroundingCardsRepositoryProvider).list();
});

class AdminGroundingCardsListScreen extends ConsumerWidget {
  const AdminGroundingCardsListScreen({super.key});

  Future<void> _desativar(BuildContext context, WidgetRef ref, GroundingCard card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Desativar cartão?'),
        content: Text('${card.titulo} deixará de aparecer na biblioteca dos usuários.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Desativar')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(adminGroundingCardsRepositoryProvider).deactivate(card.id);
      ref.invalidate(adminGroundingCardsListProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível desativar. Tente novamente.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsAsync = ref.watch(adminGroundingCardsListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Cartões de aterramento (admin)')),
      body: cardsAsync.when(
        data: (cards) {
          if (cards.isEmpty) {
            return const Center(child: Text('Nenhum cartão cadastrado ainda.'));
          }
          return ListView.builder(
            itemCount: cards.length,
            itemBuilder: (context, index) {
              final card = cards[index];
              return ListTile(
                title: Text(card.titulo + (card.ativo ? '' : ' (inativo)')),
                subtitle: Text(rotuloCategoria(card.categoria)),
                trailing: card.ativo
                    ? IconButton(
                        icon: const Icon(Icons.visibility_off_outlined),
                        tooltip: 'Desativar',
                        onPressed: () => _desativar(context, ref, card),
                      )
                    : null,
                onTap: () async {
                  final saved = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(builder: (_) => AdminGroundingCardFormScreen(card: card)),
                  );
                  if (saved == true) ref.invalidate(adminGroundingCardsListProvider);
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Não foi possível carregar os cartões.')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Novo cartão'),
        onPressed: () async {
          final saved = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const AdminGroundingCardFormScreen()),
          );
          if (saved == true) ref.invalidate(adminGroundingCardsListProvider);
        },
      ),
    );
  }
}
