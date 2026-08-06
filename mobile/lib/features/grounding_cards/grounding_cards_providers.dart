import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_providers.dart';
import 'grounding_card.dart';
import 'grounding_cards_repository.dart';

final groundingCardsRepositoryProvider = Provider<GroundingCardsRepository>((ref) {
  return GroundingCardsRepository(ref.watch(apiClientProvider).dio);
});

final groundingCardsProvider = FutureProvider.autoDispose.family<List<GroundingCard>, String?>((ref, categoria) {
  return ref.watch(groundingCardsRepositoryProvider).list(categoria: categoria);
});

final groundingCardFavoritosProvider = FutureProvider.autoDispose<List<GroundingCard>>((ref) {
  return ref.watch(groundingCardsRepositoryProvider).listFavoritos();
});
