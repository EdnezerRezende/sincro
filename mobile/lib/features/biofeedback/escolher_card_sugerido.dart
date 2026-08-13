import 'dart:math';
import '../grounding_cards/grounding_card.dart';

/// Fonte de aleatoriedade padrão para uso em produção — devolve um índice em `[0, max)`, mesmo
/// contrato de `Random.nextInt`. Testes injetam sua própria função em `escolherCardSugerido` para
/// resultados determinísticos.
int sortearIndiceAleatorio(int max) => Random().nextInt(max);

/// Escolhe o id de um grounding card para sugerir junto do alerta de estresse elevado, com
/// prioridade fixa: favoritos do usuário > categoria Respiração > qualquer card ativo. Devolve
/// `null` quando as três listas estão vazias.
String? escolherCardSugerido({
  required List<GroundingCard> favoritos,
  required List<GroundingCard> respiracaoAtivos,
  required List<GroundingCard> todosAtivos,
  required int Function(int max) sortear,
}) {
  if (favoritos.isNotEmpty) return favoritos[sortear(favoritos.length)].id;
  if (respiracaoAtivos.isNotEmpty) return respiracaoAtivos[sortear(respiracaoAtivos.length)].id;
  if (todosAtivos.isNotEmpty) return todosAtivos[sortear(todosAtivos.length)].id;
  return null;
}
