/// Limite de frequência (frequency capping) do intersticial: no máximo uma exibição a cada
/// [minInterval]. Complementa — não substitui — o limite configurado no próprio bloco do AdMob;
/// este lado do app garante o intervalo mesmo que a configuração do painel mude.
class FrequencyCap {
  FrequencyCap({required this.minInterval, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  Duration minInterval;
  final DateTime Function() _clock;
  DateTime? _lastShownAt;

  bool get canShow {
    final last = _lastShownAt;
    return last == null || _clock().difference(last) >= minInterval;
  }

  void markShown() => _lastShownAt = _clock();
}
