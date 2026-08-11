class GroundingCardFormValidationException implements Exception {
  GroundingCardFormValidationException(this.message);
  final String message;
}

void validateTitulo(String raw) {
  final texto = raw.trim();
  if (texto.isEmpty || texto.length > 100) {
    throw GroundingCardFormValidationException('Título é obrigatório e deve ter no máximo 100 caracteres.');
  }
}

void validateConteudo(String raw) {
  final texto = raw.trim();
  if (texto.isEmpty || texto.length > 2000) {
    throw GroundingCardFormValidationException('Conteúdo é obrigatório e deve ter no máximo 2000 caracteres.');
  }
}
