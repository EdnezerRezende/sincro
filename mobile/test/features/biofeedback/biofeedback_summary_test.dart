import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_summary.dart';
import 'package:sincro_mobile/features/biofeedback/estado_estresse.dart';

void main() {
  test('round-trips through toJson and fromJson with all fields present', () {
    final original = BiofeedbackSummary(
      ultimaFc: 72.0,
      mediaFcHoje: 68.5,
      mediaVfcHoje: 45.2,
      estadoEstresse: EstadoEstresse.elevado,
      atualizadoEm: DateTime.utc(2026, 8, 3, 14, 30),
    );

    final roundTripped = BiofeedbackSummary.fromJson(original.toJson());

    expect(roundTripped.ultimaFc, 72.0);
    expect(roundTripped.mediaFcHoje, 68.5);
    expect(roundTripped.mediaVfcHoje, 45.2);
    expect(roundTripped.estadoEstresse, EstadoEstresse.elevado);
    expect(roundTripped.atualizadoEm, DateTime.utc(2026, 8, 3, 14, 30));
  });

  test('round-trips with null fields (no readings yet)', () {
    final original = BiofeedbackSummary(
      ultimaFc: null,
      mediaFcHoje: null,
      mediaVfcHoje: null,
      estadoEstresse: EstadoEstresse.coletandoDados,
      atualizadoEm: DateTime.utc(2026, 8, 3, 9, 0),
    );

    final roundTripped = BiofeedbackSummary.fromJson(original.toJson());

    expect(roundTripped.ultimaFc, isNull);
    expect(roundTripped.mediaFcHoje, isNull);
    expect(roundTripped.mediaVfcHoje, isNull);
    expect(roundTripped.estadoEstresse, EstadoEstresse.coletandoDados);
  });

  test('fromJson defaults estadoEstresse to coletandoDados when the key is absent', () {
    // Resumo salvo pela Fase 1, antes deste campo existir — não pode quebrar ao ler de novo.
    final jsonAntigo = {
      'ultimaFc': 72.0,
      'mediaFcHoje': 68.5,
      'mediaVfcHoje': 45.2,
      'atualizadoEm': DateTime.utc(2026, 8, 3, 14, 30).toIso8601String(),
    };

    final lido = BiofeedbackSummary.fromJson(jsonAntigo);

    expect(lido.estadoEstresse, EstadoEstresse.coletandoDados);
  });
}
