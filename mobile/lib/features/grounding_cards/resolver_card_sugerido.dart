import 'grounding_card.dart';

/// Localiza, dentro de uma lista já buscada de cards, aquele cujo id corresponde ao sugerido por
/// uma notificação de Biofeedback. `null` quando não encontrado (card desativado/removido entre o
/// disparo do alerta e o toque, ou lista vazia).
GroundingCard? resolverCardSugerido({required List<GroundingCard> cards, required String id}) {
  for (final card in cards) {
    if (card.id == id) return card;
  }
  return null;
}
