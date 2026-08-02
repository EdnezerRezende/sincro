import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/onboarding/anamnese/anamnese_answers.dart';

void main() {
  test('fromJson parses a fully populated saved profile', () {
    final answers = AnamneseAnswers.fromJson({
      'toleranciaNotificacao': 'HORARIOS_ESPECIFICOS',
      'gatilhos': ['Abrir o app do banco', 'Ligações não agendadas'],
      'tomPreferido': 'DIRETO_E_CURTO',
      'outroGatilho': 'Filas longas',
    });

    expect(answers.toleranciaNotificacao, 'HORARIOS_ESPECIFICOS');
    expect(answers.gatilhos, ['Abrir o app do banco', 'Ligações não agendadas']);
    expect(answers.tomPreferido, 'DIRETO_E_CURTO');
    expect(answers.outroGatilho, 'Filas longas');
  });

  test('fromJson defaults gatilhos to an empty list when absent', () {
    final answers = AnamneseAnswers.fromJson({
      'toleranciaNotificacao': 'SILENCIOSAS',
      'tomPreferido': null,
    });

    expect(answers.gatilhos, isEmpty);
    expect(answers.outroGatilho, isNull);
  });

  test('round-trips through toJson and fromJson', () {
    const original = AnamneseAnswers(
      toleranciaNotificacao: 'PADRAO',
      gatilhos: ['Ambientes barulhentos'],
      tomPreferido: 'EXPLICATIVO',
      outroGatilho: 'Mudança de planos',
    );

    final restored = AnamneseAnswers.fromJson(original.toJson());

    expect(restored.toleranciaNotificacao, original.toleranciaNotificacao);
    expect(restored.gatilhos, original.gatilhos);
    expect(restored.tomPreferido, original.tomPreferido);
    expect(restored.outroGatilho, original.outroGatilho);
  });
}
