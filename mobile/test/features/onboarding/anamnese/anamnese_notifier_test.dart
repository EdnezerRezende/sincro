import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sincro_mobile/features/onboarding/anamnese/anamnese_notifier.dart';
import 'package:sincro_mobile/features/onboarding/anamnese/sensory_profile_repository.dart';

class MockSensoryProfileRepository extends Mock implements SensoryProfileRepository {}

void main() {
  late MockSensoryProfileRepository mockRepository;

  setUp(() {
    mockRepository = MockSensoryProfileRepository();
    when(() => mockRepository.upsert(any())).thenAnswer((_) async {});
  });

  test('toggling a gatilho adds and removes it', () {
    final notifier = AnamneseNotifier(mockRepository);

    notifier.toggleGatilho('Abrir o app do banco');
    expect(notifier.state.gatilhos, contains('Abrir o app do banco'));

    notifier.toggleGatilho('Abrir o app do banco');
    expect(notifier.state.gatilhos, isNot(contains('Abrir o app do banco')));
  });

  test('submit sends the current answers as dados', () async {
    final notifier = AnamneseNotifier(mockRepository);

    notifier.setTolerancia('SILENCIOSAS');
    notifier.toggleGatilho('Ligações não agendadas');
    notifier.setTom('DIRETO_E_CURTO');
    await notifier.submit();

    final captured = verify(() => mockRepository.upsert(captureAny())).captured;
    expect(captured.single, {
      'toleranciaNotificacao': 'SILENCIOSAS',
      'gatilhos': ['Ligações não agendadas'],
      'tomPreferido': 'DIRETO_E_CURTO',
    });
  });

  test('outroGatilho is included in submitted data when present', () async {
    final notifier = AnamneseNotifier(mockRepository);

    notifier.setOutroGatilho('Situações não antecipadas');
    await notifier.submit();

    final captured = verify(() => mockRepository.upsert(captureAny())).captured;
    expect(captured.single, {
      'toleranciaNotificacao': null,
      'gatilhos': [],
      'tomPreferido': null,
      'outroGatilho': 'Situações não antecipadas',
    });
  });

  test('outroGatilho is omitted from submitted data when empty', () async {
    final notifier = AnamneseNotifier(mockRepository);

    notifier.setOutroGatilho('');
    await notifier.submit();

    final captured = verify(() => mockRepository.upsert(captureAny())).captured;
    expect(captured.single, {
      'toleranciaNotificacao': null,
      'gatilhos': [],
      'tomPreferido': null,
    });
  });
}
