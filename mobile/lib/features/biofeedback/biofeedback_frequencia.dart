enum BiofeedbackFrequencia {
  quinzeMinutos(Duration(minutes: 15), '15 minutos'),
  trintaMinutos(Duration(minutes: 30), '30 minutos'),
  umaHora(Duration(hours: 1), '1 hora'),
  duasHoras(Duration(hours: 2), '2 horas');

  const BiofeedbackFrequencia(this.duracao, this.label);

  final Duration duracao;
  final String label;
}
