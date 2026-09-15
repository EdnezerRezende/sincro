import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sincro_mobile/core/dio_error_message.dart';
import 'package:sincro_mobile/features/professionals/admin_professional_form_screen.dart';
import 'package:sincro_mobile/features/professionals/location_service.dart';
import 'package:sincro_mobile/features/professionals/professionals_providers.dart';
import 'package:sincro_mobile/features/professionals/professionals_search_screen.dart';

class _FakeLocationService extends LocationService {
  _FakeLocationService(this.resultado);
  final LocationPermissionResult resultado;

  @override
  Future<LocationPermissionResult> solicitarPermissao() async => resultado;

  @override
  Future<Position> obterPosicaoAtual() async => Position(
        latitude: -23.5505,
        longitude: -46.6333,
        timestamp: DateTime(2026, 9, 15),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
}

class _ThrowingPositionLocationService extends LocationService {
  @override
  Future<LocationPermissionResult> solicitarPermissao() async => LocationPermissionResult.granted;

  @override
  Future<Position> obterPosicaoAtual() async => throw Exception('sem sinal de GPS');
}

DioException _buildDioException({dynamic responseData, int statusCode = 400}) {
  final options = RequestOptions(path: '/admin/professionals');
  return DioException(
    requestOptions: options,
    response: responseData == null
        ? null
        : Response(requestOptions: options, statusCode: statusCode, data: responseData),
  );
}

void main() {
  group('extractServerErrorMessage', () {
    test('returns a string message field as-is', () {
      final e = _buildDioException(responseData: {
        'statusCode': 400,
        'message': 'telefone must start with + followed by the country code and 10-15 digits',
        'error': 'Bad Request',
      });

      expect(
        extractServerErrorMessage(e),
        'telefone must start with + followed by the country code and 10-15 digits',
      );
    });

    test('joins an array message field with "; "', () {
      final e = _buildDioException(responseData: {
        'statusCode': 400,
        'message': ['tags should not be empty', 'bio must be shorter than or equal to 500 characters'],
        'error': 'Bad Request',
      });

      expect(
        extractServerErrorMessage(e),
        'tags should not be empty; bio must be shorter than or equal to 500 characters',
      );
    });

    test('falls back to a generic message when there is no response body', () {
      final e = _buildDioException();

      expect(extractServerErrorMessage(e), 'Não foi possível salvar. Tente novamente.');
    });

    test('falls back to a generic message when the response has no message field', () {
      final e = _buildDioException(responseData: {'statusCode': 500});

      expect(extractServerErrorMessage(e), 'Não foi possível salvar. Tente novamente.');
    });
  });

  group('Usar minha localização atual', () {
    testWidgets('"Usar minha localização atual" fills latitude and longitude', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [locationServiceProvider.overrideWithValue(_FakeLocationService(LocationPermissionResult.granted))],
        child: const MaterialApp(home: AdminProfessionalFormScreen()),
      ));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Usar minha localização atual'));
      await tester.tap(find.text('Usar minha localização atual'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, '-23.5505'), findsOneWidget);
      expect(find.widgetWithText(TextField, '-46.6333'), findsOneWidget);
    });

    testWidgets('denied permission shows the shared permission message', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [locationServiceProvider.overrideWithValue(_FakeLocationService(LocationPermissionResult.denied))],
        child: const MaterialApp(home: AdminProfessionalFormScreen()),
      ));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Usar minha localização atual'));
      await tester.tap(find.text('Usar minha localização atual'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Precisamos da sua localização'), findsOneWidget);
    });

    testWidgets('when obterPosicaoAtual throws, shows the service-disabled message and keeps the fields unchanged', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [locationServiceProvider.overrideWithValue(_ThrowingPositionLocationService())],
        child: const MaterialApp(home: AdminProfessionalFormScreen()),
      ));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Usar minha localização atual'));
      await tester.tap(find.text('Usar minha localização atual'));
      await tester.pumpAndSettle();

      expect(find.text(mensagemPermissao(LocationPermissionResult.serviceDisabled)), findsOneWidget);
      expect(find.text('-23.5505'), findsNothing);
      expect(find.text('-46.6333'), findsNothing);
    });
  });
}
