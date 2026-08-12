// mobile/test/features/biofeedback/biofeedback_alert_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_alert_service.dart';
import 'package:sincro_mobile/features/grounding_cards/grounding_card.dart';

GroundingCard _card({String id = 'card-1', String titulo = 'Respiração 4-7-8'}) => GroundingCard(
      id: id,
      titulo: titulo,
      categoria: 'RESPIRACAO',
      conteudo: 'Conteúdo',
      ativo: true,
    );

void main() {
  group('construirConteudoAlerta', () {
    test('uses the generic body and bare payload when there is no suggested card', () {
      final resultado = construirConteudoAlerta();

      expect(
        resultado.corpo,
        'Sua frequência cardíaca está um pouco diferente do seu normal agora. '
        'Talvez seja um bom momento para uma pausa.',
      );
      expect(resultado.payload, biofeedbackNotificationTapPayload);
    });

    test('mentions the card title and encodes its id in the payload when present', () {
      final resultado = construirConteudoAlerta(
        cardSugerido: _card(id: 'card-42', titulo: 'Respiração 4-7-8'),
      );

      expect(resultado.corpo, 'Que tal experimentar Respiração 4-7-8 agora?');
      expect(resultado.payload, 'biofeedback_alerta:card-42');
    });
  });

  group('BiofeedbackAlertService.extrairCardIdDoPayload', () {
    test('returns null for a null payload', () {
      expect(BiofeedbackAlertService.extrairCardIdDoPayload(null), isNull);
    });

    test('returns null for a payload unrelated to this alert type', () {
      expect(BiofeedbackAlertService.extrairCardIdDoPayload('email_triage'), isNull);
    });

    test('returns null for the bare prefix with no card id', () {
      expect(BiofeedbackAlertService.extrairCardIdDoPayload('biofeedback_alerta'), isNull);
    });

    test('returns the id when the payload has the prefix and a card id', () {
      expect(
        BiofeedbackAlertService.extrairCardIdDoPayload('biofeedback_alerta:card-42'),
        'card-42',
      );
    });
  });
}
