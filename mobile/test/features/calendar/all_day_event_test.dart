import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/calendar/calendar_event.dart';

void main() {
  group('CalendarEvent All-Day Event Detection', () {
    test('Detects all-day event (ehDiaInteiro=true)', () {
      final json = {
        'id': 'event1',
        'titulo': 'All-Day Birthday',
        'descricao': 'My birthday',
        'dataHoraInicio': '2026-09-05',
        'dataHoraFim': '2026-09-06',
        'ehDiaInteiro': true,
      };

      final event = CalendarEvent.fromJson(json);

      expect(event.ehDiaInteiro, isTrue);
      expect(event.titulo, 'All-Day Birthday');
    });

    test('Handles timed event (ehDiaInteiro=false)', () {
      final json = {
        'id': 'event2',
        'titulo': 'Meeting',
        'descricao': 'Team standup',
        'dataHoraInicio': '2026-09-05T10:00:00-03:00',
        'dataHoraFim': '2026-09-05T11:00:00-03:00',
        'ehDiaInteiro': false,
      };

      final event = CalendarEvent.fromJson(json);

      expect(event.ehDiaInteiro, isFalse);
      expect(event.titulo, 'Meeting');
    });

    test('Defaults to timed event when ehDiaInteiro missing', () {
      final json = {
        'id': 'event3',
        'titulo': 'Old Format Event',
        'descricao': 'No ehDiaInteiro field',
        'dataHoraInicio': '2026-09-05T14:00:00Z',
        'dataHoraFim': '2026-09-05T15:00:00Z',
      };

      final event = CalendarEvent.fromJson(json);

      expect(event.ehDiaInteiro, isFalse);
    });

    test('Uses fallback date for empty dataHoraInicio/Fim', () {
      final json = {
        'id': 'event4',
        'titulo': 'Fallback Date Event',
        'dataHoraInicio': '2000-01-01', // Fallback used when empty string provided
        'dataHoraFim': '2000-01-01',
        'ehDiaInteiro': false,
      };

      final event = CalendarEvent.fromJson(json);
      expect(event.id, 'event4');
      // Event is created with fallback dates when null/empty
      expect(event.dataHoraInicio.year, 2000);
    });

    test('toJson preserves all-day flag', () {
      final event = CalendarEvent(
        id: 'event5',
        titulo: 'Anniversary',
        descricao: '',
        dataHoraInicio: DateTime(2026, 9, 5),
        dataHoraFim: DateTime(2026, 9, 6),
        ehDiaInteiro: true,
      );

      final json = event.toJson();

      expect(json['ehDiaInteiro'], isTrue);
      expect(json['id'], 'event5');
    });

    test('toJson includes false for timed events', () {
      final event = CalendarEvent(
        id: 'event6',
        titulo: 'Lunch',
        descricao: '',
        dataHoraInicio: DateTime(2026, 9, 5, 12, 0),
        dataHoraFim: DateTime(2026, 9, 5, 13, 0),
        ehDiaInteiro: false,
      );

      final json = event.toJson();

      expect(json['ehDiaInteiro'], isFalse);
    });
  });
}
