final _whatsappRegex = RegExp(r'^\+\d{10,15}$');

String relacaoFromTags(List<String> tags) {
  final lower = tags.map((t) => t.toLowerCase()).toList();
  if (lower.any((t) => t.contains('psiquiat'))) return 'PSIQUIATRA';
  if (lower.any((t) => t.contains('psic'))) return 'PSICOLOGO';
  if (lower.any((t) => t.contains('t.o') || t.contains('terapeuta ocupacional'))) return 'T.O.';
  return 'OUTRO';
}

String normalizarTelefone(String telefone) => telefone.replaceAll(RegExp(r'[\s()\-]'), '');

bool telefoneValidoParaContato(String telefone) => _whatsappRegex.hasMatch(normalizarTelefone(telefone));
