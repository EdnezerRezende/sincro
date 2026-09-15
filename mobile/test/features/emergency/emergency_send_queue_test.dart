import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/emergency/emergency_message.dart';
import 'package:sincro_mobile/features/emergency/emergency_send_queue.dart';

EmergencyMessage _msg(String id, String name) => EmergencyMessage(
      contactId: id, contactName: name, whatsapp: '+5511999999999', message: 'Oi', waUrl: 'https://wa.me/$id');

void main() {
  test('queue walks messages in order and reports done', () {
    final queue = EmergencySendQueue([_msg('c1', 'Marina Souza'), _msg('c2', 'João')]);

    expect(queue.total, 2);
    expect(queue.index, 0);
    expect(queue.current!.contactId, 'c1');
    expect(queue.last, isNull);
    expect(queue.isDone, isFalse);

    queue.markCurrentOpened();
    expect(queue.index, 1);
    expect(queue.last!.contactId, 'c1');
    expect(queue.current!.contactId, 'c2');

    queue.markCurrentOpened();
    expect(queue.isDone, isTrue);
    expect(queue.current, isNull);
  });

  test('markCurrentOpened after done is a no-op', () {
    final queue = EmergencySendQueue([_msg('c1', 'Marina')]);
    queue.markCurrentOpened();
    queue.markCurrentOpened();
    expect(queue.index, 1);
  });

  test('CTA label depends on how many contacts are selected', () {
    expect(emergencyCtaLabel(0, const []), 'Escolha quem avisar');
    expect(emergencyCtaLabel(1, const ['Marina']), 'Abrir WhatsApp para Marina');
    expect(emergencyCtaLabel(3, const ['Marina', 'João', 'Ana']), 'Abrir WhatsApp · 1 de 3: Marina');
  });
}
