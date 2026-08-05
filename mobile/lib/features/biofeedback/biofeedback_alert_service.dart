import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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

class BiofeedbackAlertService {
  BiofeedbackAlertService(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  Future<void> mostrarAlerta() async {
    const detalhes = NotificationDetails(
      android: AndroidNotificationDetails(
        _idCanalAndroid,
        _nomeCanalAndroid,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _plugin.show(
      id: _idNotificacao,
      title: _tituloAlerta,
      body: _corpoAlerta,
      notificationDetails: detalhes,
      payload: biofeedbackNotificationTapPayload,
    );
  }
}
