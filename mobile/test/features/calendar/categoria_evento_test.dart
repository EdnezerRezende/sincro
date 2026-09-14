import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/calendar/calendar_event.dart';

void main() {
  group('CalendarEvent.categoria', () {
    test('parses FINANCEIRO com lancamentoId', () {
      final event = CalendarEvent.fromJson({
        'id': 'ev1',
        'titulo': 'Pagar: Nubank',
        'descricao': '',
        'dataHoraInicio': '2026-09-10',
        'dataHoraFim': '2026-09-10',
        'ehDiaInteiro': true,
        'categoria': 'FINANCEIRO',
        'lancamentoId': 'lanc-1',
      });

      expect(event.categoria, CategoriaEvento.financeiro);
      expect(event.lancamentoId, 'lanc-1');
      expect(event.isGeradoPorFinancas, isTrue);
    });

    test('parses SOCIAL, TRABALHO e GERAL', () {
      for (final par in {
        'SOCIAL': CategoriaEvento.social,
        'TRABALHO': CategoriaEvento.trabalho,
        'GERAL': CategoriaEvento.geral,
      }.entries) {
        final event = CalendarEvent.fromJson({
          'id': 'ev1',
          'titulo': 'Evento',
          'descricao': '',
          'dataHoraInicio': '2026-09-10T10:00:00-03:00',
          'dataHoraFim': '2026-09-10T11:00:00-03:00',
          'categoria': par.key,
        });
        expect(event.categoria, par.value);
      }
    });

    test('cai em GERAL quando categoria ausente ou desconhecida', () {
      final semCampo = CalendarEvent.fromJson({
        'id': 'ev1', 'titulo': 'Evento', 'descricao': '',
        'dataHoraInicio': '2026-09-10T10:00:00-03:00', 'dataHoraFim': '2026-09-10T11:00:00-03:00',
      });
      expect(semCampo.categoria, CategoriaEvento.geral);

      final desconhecida = CalendarEvent.fromJson({
        'id': 'ev1', 'titulo': 'Evento', 'descricao': '',
        'dataHoraInicio': '2026-09-10T10:00:00-03:00', 'dataHoraFim': '2026-09-10T11:00:00-03:00',
        'categoria': 'ALGO_INVALIDO',
      });
      expect(desconhecida.categoria, CategoriaEvento.geral);
    });

    test('isGeradoPorFinancas é false sem lancamentoId, mesmo com categoria FINANCEIRO', () {
      final event = CalendarEvent.fromJson({
        'id': 'ev1', 'titulo': 'Evento', 'descricao': '',
        'dataHoraInicio': '2026-09-10T10:00:00-03:00', 'dataHoraFim': '2026-09-10T11:00:00-03:00',
        'categoria': 'FINANCEIRO',
      });
      expect(event.isGeradoPorFinancas, isFalse);
    });

    test('toJson serializa a categoria em maiúsculas', () {
      final event = CalendarEvent(
        id: 'ev1',
        titulo: 'Evento',
        descricao: '',
        dataHoraInicio: DateTime(2026, 9, 10),
        dataHoraFim: DateTime(2026, 9, 10),
        categoria: CategoriaEvento.trabalho,
      );
      expect(event.toJson()['categoria'], 'TRABALHO');
    });
  });
}
