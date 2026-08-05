import 'estado_estresse.dart';

bool deveAlertar({
  required EstadoEstresse? estadoAnterior,
  required EstadoEstresse estadoNovo,
  required bool alertasAtivos,
  required String? tolerancia,
}) {
  if (estadoAnterior == EstadoEstresse.elevado) return false;
  if (estadoNovo != EstadoEstresse.elevado) return false;
  if (!alertasAtivos) return false;
  return tolerancia == 'PADRAO';
}
