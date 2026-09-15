import 'emergency_message.dart';

/// Fila de abertura do WhatsApp: `wa.me` abre UMA conversa por vez, então a folha
/// abre uma, espera o app voltar ao primeiro plano e oferece a próxima.
class EmergencySendQueue {
  EmergencySendQueue(this._messages);

  final List<EmergencyMessage> _messages;
  int _index = 0;

  int get index => _index;
  int get total => _messages.length;
  bool get isDone => _index >= _messages.length;
  EmergencyMessage? get current => isDone ? null : _messages[_index];
  EmergencyMessage? get last => _index == 0 ? null : _messages[_index - 1];

  void markCurrentOpened() {
    if (!isDone) _index++;
  }
}

String emergencyCtaLabel(int selectedCount, List<String> selectedFirstNames) {
  if (selectedCount == 0) return 'Escolha quem avisar';
  final first = selectedFirstNames.first;
  if (selectedCount == 1) return 'Abrir WhatsApp para $first';
  return 'Abrir WhatsApp · 1 de $selectedCount: $first';
}

String primeiroNome(String nomeCompleto) => nomeCompleto.trim().split(' ').first;
