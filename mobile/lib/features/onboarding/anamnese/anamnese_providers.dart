import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api_providers.dart';
import 'anamnese_answers.dart';
import 'anamnese_notifier.dart';
import 'sensory_profile_repository.dart';

final sensoryProfileRepositoryProvider = Provider<SensoryProfileRepository>((ref) {
  return SensoryProfileRepository(ref.watch(apiClientProvider).dio);
});

class _AnamneseNotifierWrapper extends Notifier<AnamneseAnswers> {
  late AnamneseNotifier _notifier;

  @override
  AnamneseAnswers build() {
    _notifier = AnamneseNotifier(ref.watch(sensoryProfileRepositoryProvider));
    return _notifier.state;
  }

  void setTolerancia(String value) {
    _notifier.setTolerancia(value);
    state = _notifier.state;
  }

  void toggleGatilho(String gatilho) {
    _notifier.toggleGatilho(gatilho);
    state = _notifier.state;
  }

  void setTom(String value) {
    _notifier.setTom(value);
    state = _notifier.state;
  }

  Future<void> submit() async {
    await _notifier.submit();
  }
}

final anamneseNotifierProvider = NotifierProvider<_AnamneseNotifierWrapper, AnamneseAnswers>(() {
  return _AnamneseNotifierWrapper();
});
