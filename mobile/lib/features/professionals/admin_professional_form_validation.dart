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

final RegExp _telefoneRegExp = RegExp(r'^\+\d{10,15}$');

void validateTelefone(String raw) {
  if (!_telefoneRegExp.hasMatch(raw.trim())) {
    throw ProfessionalFormValidationException(
      'Telefone inválido. Use o formato +DDI seguido de 10 a 15 dígitos, ex: +5511999999999.',
    );
  }
}

void validateBio(String raw) {
  final texto = raw.trim();
  if (texto.isEmpty || texto.length > 500) {
    throw ProfessionalFormValidationException('Bio é obrigatória e deve ter no máximo 500 caracteres.');
  }
}

void validateTags(List<String> tags) {
  if (tags.isEmpty) {
    throw ProfessionalFormValidationException('Selecione ao menos uma tag.');
  }
}
