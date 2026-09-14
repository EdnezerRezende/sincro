import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/calendar/calendar_event.dart';
import 'package:sincro_mobile/features/calendar/calendar_repository.dart';

void main() {
  group('CalendarRepository.createEvent — categoria', () {
    test('envia categoria GERAL por padrão quando não informada', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        expect(options.data['categoria'], 'GERAL');
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: {
            'id': 'ev1', 'titulo': 'Evento', 'descricao': '',
            'dataHoraInicio': '2026-09-10T10:00:00-03:00',
            'dataHoraFim': '2026-09-10T11:00:00-03:00', 'categoria': 'GERAL',
          },
        ));
      }));
      final repo = CalendarRepository(dio);

      await repo.createEvent(
        titulo: 'Evento',
        descricao: '',
        dataHoraInicio: DateTime(2026, 9, 10, 10),
        dataHoraFim: DateTime(2026, 9, 10, 11),
      );
    });

    test('envia a categoria informada', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        expect(options.data['categoria'], 'TRABALHO');
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: {
            'id': 'ev1', 'titulo': 'Reunião', 'descricao': '',
            'dataHoraInicio': '2026-09-10T10:00:00-03:00',
            'dataHoraFim': '2026-09-10T11:00:00-03:00', 'categoria': 'TRABALHO',
          },
        ));
      }));
      final repo = CalendarRepository(dio);

      await repo.createEvent(
        titulo: 'Reunião',
        descricao: '',
        dataHoraInicio: DateTime(2026, 9, 10, 10),
        dataHoraFim: DateTime(2026, 9, 10, 11),
        categoria: CategoriaEvento.trabalho,
      );
    });

    test('updateEvent também envia a categoria informada', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        expect(options.path, '/calendario/evento/ev1');
        expect(options.data['categoria'], 'SOCIAL');
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: {
            'id': 'ev1', 'titulo': 'Festa', 'descricao': '',
            'dataHoraInicio': '2026-09-10T10:00:00-03:00',
            'dataHoraFim': '2026-09-10T11:00:00-03:00', 'categoria': 'SOCIAL',
          },
        ));
      }));
      final repo = CalendarRepository(dio);

      await repo.updateEvent(
        eventId: 'ev1',
        titulo: 'Festa',
        descricao: '',
        dataHoraInicio: DateTime(2026, 9, 10, 10),
        dataHoraFim: DateTime(2026, 9, 10, 11),
        categoria: CategoriaEvento.social,
      );
    });
  });
}
