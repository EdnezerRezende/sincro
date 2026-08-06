class ProfessionalFormValidationException implements Exception {
  ProfessionalFormValidationException(this.message);
  final String message;
}

List<String> parseTags(String raw) {
  return raw.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
}

double parseCoordenada(String raw, {required double min, required double max, required String campo}) {
  final valor = double.tryParse(raw.trim());
  if (valor == null || valor < min || valor > max) {
    throw ProfessionalFormValidationException('$campo inválido(a). Use um valor entre $min e $max.');
  }
  return valor;
}
