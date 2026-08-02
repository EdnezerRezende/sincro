import 'anamnese_answers.dart';
import 'sensory_profile_repository.dart';

class AnamneseNotifier {
  AnamneseNotifier(SensoryProfileRepository repository) : _repository = repository, state = const AnamneseAnswers();

  final SensoryProfileRepository _repository;
  AnamneseAnswers state;

  void setTolerancia(String value) {
    state = state.copyWith(toleranciaNotificacao: value);
  }

  void toggleGatilho(String gatilho) {
    final gatilhos = List<String>.from(state.gatilhos);
    if (gatilhos.contains(gatilho)) {
      gatilhos.remove(gatilho);
    } else {
      gatilhos.add(gatilho);
    }
    state = state.copyWith(gatilhos: gatilhos);
  }

  void setTom(String value) {
    state = state.copyWith(tomPreferido: value);
  }

  void setOutroGatilho(String? value) {
    state = state.copyWith(outroGatilho: value);
  }

  Future<void> submit() async {
    await _repository.upsert(state.toJson());
  }
}
