import 'anamnese_answers.dart';

class AnamneseNotifier {
  AnamneseNotifier(dynamic repository) : _repository = repository, state = const AnamneseAnswers();

  final dynamic _repository;
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
