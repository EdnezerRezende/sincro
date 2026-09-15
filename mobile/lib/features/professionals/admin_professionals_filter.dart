import 'professional.dart';

List<Professional> filtrarProfissionaisAdmin(List<Professional> todos, {required String termo, required bool mostrarInativos}) {
  final t = termo.trim().toLowerCase();
  return todos.where((p) {
    if (!mostrarInativos && !p.ativo) return false;
    if (t.isEmpty) return true;
    return p.nome.toLowerCase().contains(t) ||
        p.cidade.toLowerCase().contains(t) ||
        p.tags.any((tag) => tag.toLowerCase().contains(t));
  }).toList();
}

String resumoContagem(List<Professional> todos) {
  final ativos = todos.where((p) => p.ativo).length;
  final inativos = todos.length - ativos;
  return '$ativos ${ativos == 1 ? 'ativo' : 'ativos'} · $inativos ${inativos == 1 ? 'inativo' : 'inativos'}';
}
