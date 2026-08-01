import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/onboarding/anamnese/anamnese_notifier.dart';

class _FakeSensoryProfileRepository {
  Map<String, dynamic>? lastSubmittedDados;

  Future<void> upsert(Map<String, dynamic> dados) async {
    lastSubmittedDados = dados;
  }
}

void main() {
  test('toggling a gatilho adds and removes it', () {
    final notifier = AnamneseNotifier(_FakeSensoryProfileRepository() as dynamic);

    notifier.toggleGatilho('Abrir o app do banco');
    expect(notifier.state.gatilhos, contains('Abrir o app do banco'));

    notifier.toggleGatilho('Abrir o app do banco');
    expect(notifier.state.gatilhos, isNot(contains('Abrir o app do banco')));
  });

  test('submit sends the current answers as dados', () async {
    final fakeRepo = _FakeSensoryProfileRepository();
    final notifier = AnamneseNotifier(fakeRepo as dynamic);

    notifier.setTolerancia('SILENCIOSAS');
    notifier.toggleGatilho('Ligações não agendadas');
    notifier.setTom('DIRETO_E_CURTO');
    await notifier.submit();

    expect(fakeRepo.lastSubmittedDados, {
      'toleranciaNotificacao': 'SILENCIOSAS',
      'gatilhos': ['Ligações não agendadas'],
      'tomPreferido': 'DIRETO_E_CURTO',
    });
  });

  test('outroGatilho is included in submitted data when present', () async {
    final fakeRepo = _FakeSensoryProfileRepository();
    final notifier = AnamneseNotifier(fakeRepo as dynamic);

    notifier.setOutroGatilho('Situações não antecipadas');
    await notifier.submit();

    expect(fakeRepo.lastSubmittedDados, {
      'toleranciaNotificacao': null,
      'gatilhos': [],
      'tomPreferido': null,
      'outroGatilho': 'Situações não antecipadas',
    });
  });

  test('outroGatilho is omitted from submitted data when empty', () async {
    final fakeRepo = _FakeSensoryProfileRepository();
    final notifier = AnamneseNotifier(fakeRepo as dynamic);

    notifier.setOutroGatilho('');
    await notifier.submit();

    expect(fakeRepo.lastSubmittedDados, {
      'toleranciaNotificacao': null,
      'gatilhos': [],
      'tomPreferido': null,
    });
  });
}
