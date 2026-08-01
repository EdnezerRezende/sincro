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
}
