import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'grounding_card_detail_screen.dart';
import 'grounding_cards_providers.dart';
import 'resolver_card_sugerido.dart';

/// Elo entre a notificação de alerta do Biofeedback e a tela de detalhe de um grounding card: lê
/// o id recebido como argumento de rota, localiza o card na lista já mantida pelas providers
/// existentes e mostra o detalhe — ou cai silenciosamente para `/biofeedback` se o card não for
/// encontrado (desativado/removido entre o disparo do alerta e o toque) ou a busca falhar.
class GroundingCardSugeridoScreen extends ConsumerWidget {
  const GroundingCardSugeridoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardId = ModalRoute.of(context)!.settings.arguments as String;
    final cardsAsync = ref.watch(groundingCardsProvider(null));
    final favoritosAsync = ref.watch(groundingCardFavoritosProvider);

    // Aguarda os favoritos também estarem prontos antes de renderizar o detalhe: como
    // GroundingCardDetailScreen copia favoritadoInicial para estado local só em initState (sem
    // didUpdateWidget), renderizar mais cedo com favoritosAsync ainda carregando fixaria o
    // coração como "não favoritado" permanentemente, mesmo que os favoritos cheguem em seguida.
    // Um erro na busca de favoritos, por outro lado, já degrada graciosamente para "não
    // favoritado" via o maybeWhen abaixo — não precisa bloquear a renderização.
    if (favoritosAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return cardsAsync.when(
      data: (cards) {
        final card = resolverCardSugerido(cards: cards, id: cardId);
        if (card == null) return const _RedirectToBiofeedback();

        final favoritosIds = favoritosAsync.maybeWhen(
          data: (favoritos) => favoritos.map((c) => c.id).toSet(),
          orElse: () => const <String>{},
        );
        return GroundingCardDetailScreen(
          card: card,
          favoritadoInicial: favoritosIds.contains(card.id),
        );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const _RedirectToBiofeedback(),
    );
  }
}

/// Mesmo padrão de redirecionamento pós-build já usado em `OnboardingRouterScreen`
/// (`features/onboarding/onboarding_router.dart`) — evita chamar `Navigator` durante `build()`.
class _RedirectToBiofeedback extends StatefulWidget {
  const _RedirectToBiofeedback();

  @override
  State<_RedirectToBiofeedback> createState() => _RedirectToBiofeedbackState();
}

class _RedirectToBiofeedbackState extends State<_RedirectToBiofeedback> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacementNamed('/biofeedback');
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}
