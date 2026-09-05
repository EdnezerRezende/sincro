import 'package:dio/dio.dart';
import 'calendar_event.dart';

/// Lançada quando o backend recusa acesso à agenda porque o usuário ainda não concedeu (ou
/// revogou) o escopo do Google Calendar — o backend responde 403 quando `temEscopoAgenda` é
/// false (ver `CalendarController.refreshTokenComEscopoAgenda`). É distinta de uma falha de rede
/// genérica: sem essa distinção, "sem eventos esta semana" e "agenda nunca foi conectada" ficam
/// indistinguíveis para a UI (que hoje mostra lista vazia para ambos os casos).
class CalendarScopeException implements Exception {
  const CalendarScopeException([this.message = 'Reconecte o Gmail para usar a agenda.']);

  final String message;

  @override
  String toString() => 'CalendarScopeException: $message';
}

/// Lançada para falhas identificáveis como reais (timeout, 5xx, ou qualquer resposta de erro que
/// não seja o 403 de escopo já tratado por [CalendarScopeException]) — para que a UI não confunda
/// "o backend caiu" com "a agenda está genuinamente vazia". Uma falha de conectividade pura (sem
/// resposta do servidor, ex.: dispositivo offline) ainda cai no best-effort de retornar lista
/// vazia; ver comentário em [_isFalhaPersistente].
class CalendarUnavailableException implements Exception {
  const CalendarUnavailableException([
    this.message = 'Não foi possível carregar a agenda agora.',
  ]);

  final String message;

  @override
  String toString() => 'CalendarUnavailableException: $message';
}

/// Serializa um DateTime LOCAL preservando seu offset de fuso explícito (ex.:
/// "2026-09-01T15:00:00.000-03:00"), em vez de `DateTime.toIso8601String()` puro — que numa
/// instância local NÃO inclui offset algum. Uma string sem offset é resolvida pelo backend como
/// UTC (`comOffsetExplicito` em `calendar-api-client.service.ts`), reintroduzindo o bug que o
/// código original já tinha corrigido: um evento marcado às 15h no fuso do usuário (-03:00) era
/// salvo/exibido como 18h.
String _isoComOffsetLocal(DateTime dt) {
  if (dt.isUtc) return dt.toIso8601String();
  final base = dt.toIso8601String();
  final offset = dt.timeZoneOffset;
  final sinal = offset.isNegative ? '-' : '+';
  final minutosAbsolutos = offset.inMinutes.abs();
  final horas = (minutosAbsolutos ~/ 60).toString().padLeft(2, '0');
  final minutos = (minutosAbsolutos % 60).toString().padLeft(2, '0');
  return '$base$sinal$horas:$minutos';
}

/// Repository para chamadas ao backend de calendário.
/// Gerencia sincronização de eventos do Google Calendar e criação/edição de eventos.
class CalendarRepository {
  CalendarRepository(this._dio);

  final Dio _dio;

  /// Lista eventos dos próximos 7 dias, sincronizados do Google Calendar.
  /// Falhas de rede genéricas retornam lista vazia (best-effort, mantém o padrão do app); uma
  /// recusa por falta do escopo de agenda (403) é relançada como [CalendarScopeException] para
  /// que a UI possa diferenciar "sem eventos" de "agenda não conectada".
  Future<List<CalendarEvent>> listUpcomingEvents() async {
    try {
      final response = await _dio.get('/calendario/eventos-proximos');
      return _parseEvents(response.data);
    } on DioException catch (e) {
      if (_isScopeForbidden(e)) throw const CalendarScopeException();
      if (_isFalhaPersistente(e)) throw const CalendarUnavailableException();
      return [];
    }
  }

  /// Lista eventos de um mês específico (para visualização no calendário).
  /// Mesma distinção de erro que [listUpcomingEvents].
  Future<List<CalendarEvent>> listMonthEvents(int ano, int mes) async {
    try {
      final response = await _dio.get(
        '/calendario/eventos-mes',
        queryParameters: {'ano': ano, 'mes': mes},
      );
      return _parseEvents(response.data);
    } on DioException catch (e) {
      if (_isScopeForbidden(e)) throw const CalendarScopeException();
      if (_isFalhaPersistente(e)) throw const CalendarUnavailableException();
      return [];
    }
  }

  /// Cria um novo evento no Google Calendar do usuário e retorna o evento criado (com o id real
  /// atribuído pelo Google). Se a criação falhar, lança erro para que a UI possa mostrar feedback.
  /// Se `ehDiaInteiro` é true, o evento é criado como um evento de dia inteiro (all-day),
  /// preservando esse status no Google Calendar.
  Future<CalendarEvent> createEvent({
    required String titulo,
    required String descricao,
    required DateTime dataHoraInicio,
    required DateTime dataHoraFim,
    bool ehDiaInteiro = false,
  }) async {
    final response = await _dio.post(
      '/calendario/criar-evento',
      data: {
        'titulo': titulo,
        'descricao': descricao,
        'dataHoraInicio': _isoComOffsetLocal(dataHoraInicio),
        'dataHoraFim': _isoComOffsetLocal(dataHoraFim),
        'ehDiaInteiro': ehDiaInteiro,
      },
    );
    return CalendarEvent.fromJson(response.data as Map<String, dynamic>);
  }

  /// Atualiza um evento existente no Google Calendar.
  /// Se `ehDiaInteiro` é true, preserva o evento como um evento de dia inteiro (all-day),
  /// evitando corrupção silenciosa ao editar.
  Future<CalendarEvent> updateEvent({
    required String eventId,
    required String titulo,
    required String descricao,
    required DateTime dataHoraInicio,
    required DateTime dataHoraFim,
    bool ehDiaInteiro = false,
  }) async {
    final response = await _dio.put(
      '/calendario/evento/$eventId',
      data: {
        'titulo': titulo,
        'descricao': descricao,
        'dataHoraInicio': _isoComOffsetLocal(dataHoraInicio),
        'dataHoraFim': _isoComOffsetLocal(dataHoraFim),
        'ehDiaInteiro': ehDiaInteiro,
      },
    );
    return CalendarEvent.fromJson(response.data as Map<String, dynamic>);
  }

  /// Deleta um evento do Google Calendar.
  Future<void> deleteEvent(String eventId) async {
    await _dio.delete('/calendario/evento/$eventId');
  }

  List<CalendarEvent> _parseEvents(dynamic data) {
    return (data as List?)
            ?.map((e) => CalendarEvent.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
  }

  bool _isScopeForbidden(DioException e) => e.response?.statusCode == 403;

  /// Timeouts e qualquer resposta de erro do servidor (4xx que não seja o 403 de escopo já
  /// tratado, ou 5xx) são falhas reais que a UI não deveria disfarçar de "sem eventos". Uma falha
  /// de conectividade pura (sem resposta nenhuma do servidor — dispositivo offline, DNS, etc.)
  /// ainda cai no best-effort de retornar lista vazia: uma checagem explícita de conectividade
  /// ficaria mais completa, mas é o tradeoff aceito nesta rodada.
  bool _isFalhaPersistente(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.badResponse:
        return true;
      default:
        return false;
    }
  }
}
