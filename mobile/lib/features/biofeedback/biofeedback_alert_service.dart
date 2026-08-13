import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../grounding_cards/grounding_card.dart';

/// Usado tanto pelo `payload` desta notificação quanto pelo handler de toque em `main.dart`, para
/// os dois nunca ficarem dessincronizados.
const biofeedbackNotificationTapPayload = 'biofeedback_alerta';

const _idNotificacao = 100;
const _idCanalAndroid = 'biofeedback_alertas';
const _nomeCanalAndroid = 'Alertas de bem-estar';
const _tituloAlerta = 'Um momento para respirar';
const _corpoAlerta =
    'Sua frequência cardíaca está um pouco diferente do seu normal agora. '
    'Talvez seja um bom momento para uma pausa.';

/// Corpo e payload da notificação de alerta, extraídos de `mostrarAlerta` para serem testáveis
/// sem tocar `FlutterLocalNotificationsPlugin` (não há precedente de mock desse plugin neste
/// projeto). Sem `cardSugerido`, mantém o texto genérico e o payload de sempre; com ele, menciona
/// o título do card (não é dado de saúde — conteúdo público/curado) e encapsula o id no payload.
({String corpo, String payload}) construirConteudoAlerta({GroundingCard? cardSugerido}) {
  final corpo = cardSugerido != null
      ? 'Que tal experimentar ${cardSugerido.titulo} agora?'
      : _corpoAlerta;
  final payload = cardSugerido != null
      ? '$biofeedbackNotificationTapPayload:${cardSugerido.id}'
      : biofeedbackNotificationTapPayload;
  return (corpo: corpo, payload: payload);
}

class BiofeedbackAlertService {
  BiofeedbackAlertService(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  Future<void> mostrarAlerta({GroundingCard? cardSugerido}) async {
    const detalhes = NotificationDetails(
      android: AndroidNotificationDetails(
        _idCanalAndroid,
        _nomeCanalAndroid,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(),
    );
    final conteudo = construirConteudoAlerta(cardSugerido: cardSugerido);
    await _plugin.show(
      id: _idNotificacao,
      title: _tituloAlerta,
      body: conteudo.corpo,
      notificationDetails: detalhes,
      payload: conteudo.payload,
    );
  }

  /// Extrai o id do card sugerido de um payload de notificação, se houver. `null` para payload
  /// nulo, para um payload de outro tipo de notificação, e para o prefixo sem id (alerta sem
  /// card sugerido).
  static String? extrairCardIdDoPayload(String? payload) {
    if (payload == null) return null;
    if (!payload.startsWith(biofeedbackNotificationTapPayload)) return null;
    final resto = payload.substring(biofeedbackNotificationTapPayload.length);
    if (!resto.startsWith(':')) return null;
    final id = resto.substring(1);
    return id.isEmpty ? null : id;
  }
}
