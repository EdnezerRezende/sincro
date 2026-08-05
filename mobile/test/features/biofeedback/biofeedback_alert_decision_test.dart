import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_alert_decision.dart';
import 'package:sincro_mobile/features/biofeedback/estado_estresse.dart';

void main() {
  test('alerts on the transition from calmo to elevado', () {
    final resultado = deveAlertar(
      estadoAnterior: EstadoEstresse.calmo,
      estadoNovo: EstadoEstresse.elevado,
      alertasAtivos: true,
      tolerancia: 'PADRAO',
    );

    expect(resultado, true);
  });

  test('alerts on the transition from coletandoDados to elevado', () {
    final resultado = deveAlertar(
      estadoAnterior: EstadoEstresse.coletandoDados,
      estadoNovo: EstadoEstresse.elevado,
      alertasAtivos: true,
      tolerancia: 'PADRAO',
    );

    expect(resultado, true);
  });

  test('alerts when there was no previous summary at all (estadoAnterior null)', () {
    final resultado = deveAlertar(
      estadoAnterior: null,
      estadoNovo: EstadoEstresse.elevado,
      alertasAtivos: true,
      tolerancia: 'PADRAO',
    );

    expect(resultado, true);
  });

  test('does not alert when already elevado (elevado to elevado)', () {
    final resultado = deveAlertar(
      estadoAnterior: EstadoEstresse.elevado,
      estadoNovo: EstadoEstresse.elevado,
      alertasAtivos: true,
      tolerancia: 'PADRAO',
    );

    expect(resultado, false);
  });

  test('does not alert when leaving elevado (elevado to calmo)', () {
    final resultado = deveAlertar(
      estadoAnterior: EstadoEstresse.elevado,
      estadoNovo: EstadoEstresse.calmo,
      alertasAtivos: true,
      tolerancia: 'PADRAO',
    );

    expect(resultado, false);
  });

  test('does not alert when the new state is not elevado (calmo to calmo)', () {
    final resultado = deveAlertar(
      estadoAnterior: EstadoEstresse.calmo,
      estadoNovo: EstadoEstresse.calmo,
      alertasAtivos: true,
      tolerancia: 'PADRAO',
    );

    expect(resultado, false);
  });

  test('does not alert when alertasAtivos is false, even on a valid transition', () {
    final resultado = deveAlertar(
      estadoAnterior: EstadoEstresse.calmo,
      estadoNovo: EstadoEstresse.elevado,
      alertasAtivos: false,
      tolerancia: 'PADRAO',
    );

    expect(resultado, false);
  });

  test('does not alert when tolerancia is not PADRAO, even on a valid transition', () {
    final resultado = deveAlertar(
      estadoAnterior: EstadoEstresse.calmo,
      estadoNovo: EstadoEstresse.elevado,
      alertasAtivos: true,
      tolerancia: 'HORARIO_ESPECIFICO',
    );

    expect(resultado, false);
  });

  test('does not alert when tolerancia is null', () {
    final resultado = deveAlertar(
      estadoAnterior: EstadoEstresse.calmo,
      estadoNovo: EstadoEstresse.elevado,
      alertasAtivos: true,
      tolerancia: null,
    );

    expect(resultado, false);
  });
}
