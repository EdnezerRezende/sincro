import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_alert_service.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_cache.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_health_service.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_providers.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_screen.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_stress_detector.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_summary_calculator.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_sync_service.dart';
import 'package:sincro_mobile/features/grounding_cards/grounding_cards_repository.dart';
import 'package:sincro_mobile/features/onboarding/anamnese/sensory_profile_repository.dart';

class _ThrowingSyncService extends BiofeedbackSyncService {
  _ThrowingSyncService()
    : super(
        BiofeedbackHealthService(),
        BiofeedbackCache(),
        BiofeedbackSummaryCalculator(),
        BiofeedbackStressDetector(),
        BiofeedbackAlertService(FlutterLocalNotificationsPlugin()),
        SensoryProfileRepository(Dio()),
        GroundingCardsRepository(Dio()),
      );

  @override
  Future<void> sincronizar({DateTime? agora}) {
    throw Exception('falha de sincronização simulada');
  }
}

Widget _app({required bool? permissao}) {
  return ProviderScope(
    overrides: [
      biofeedbackResumoProvider.overrideWith((ref) async => null),
      biofeedbackDiasNoHistoricoProvider.overrideWith((ref) async => 0),
      biofeedbackPermissaoProvider.overrideWith((ref) async => permissao),
      biofeedbackSyncServiceProvider.overrideWithValue(_ThrowingSyncService()),
    ],
    child: MaterialApp(theme: sincroLightTheme, home: const BiofeedbackScreen()),
  );
}

void main() {
  testWidgets('shows the generic empty message when permission status is unknown (null)', (
    tester,
  ) async {
    await tester.pumpWidget(_app(permissao: null));
    await tester.pumpAndSettle();

    expect(find.textContaining('Nenhum dado ainda'), findsOneWidget);
    expect(find.text('Conceder acesso'), findsNothing);
  });

  testWidgets('shows a permission-specific message and a grant button when denied (false)', (
    tester,
  ) async {
    await tester.pumpWidget(_app(permissao: false));
    await tester.pumpAndSettle();

    expect(find.textContaining('Sem acesso aos dados de saúde'), findsOneWidget);
    expect(find.text('Conceder acesso'), findsOneWidget);
  });

  testWidgets('shows a calm error message when pull-to-refresh sync fails', (tester) async {
    await tester.pumpWidget(_app(permissao: true));
    await tester.pumpAndSettle();

    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    expect(find.textContaining('Não foi possível sincronizar agora'), findsOneWidget);
  });
}
