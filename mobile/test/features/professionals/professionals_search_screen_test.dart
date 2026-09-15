import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sincro_mobile/features/professionals/location_service.dart';
import 'package:sincro_mobile/features/professionals/professionals_providers.dart';
import 'package:sincro_mobile/features/professionals/professionals_repository.dart';
import 'package:sincro_mobile/features/professionals/professionals_search_screen.dart';

class _FakeLocationService extends LocationService {
  _FakeLocationService(this.resultado);

  final LocationPermissionResult resultado;
  int abrirConfiguracoesChamadas = 0;

  @override
  Future<LocationPermissionResult> solicitarPermissao() async => resultado;

  @override
  Future<void> abrirConfiguracoesDoApp() async {
    abrirConfiguracoesChamadas++;
  }

  @override
  Future<Position> obterPosicaoAtual() async => Position(
    latitude: 0,
    longitude: 0,
    timestamp: DateTime(2026),
    accuracy: 0,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

ProfessionalsRepository _buildFakeRepository() {
  final dio = Dio(BaseOptions(baseUrl: 'http://test'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response(requestOptions: options, statusCode: 200, data: []),
        );
      },
    ),
  );
  return ProfessionalsRepository(dio);
}

void main() {
  test('mensagemPermissao is empty when permission is granted', () {
    expect(mensagemPermissao(LocationPermissionResult.granted), '');
  });

  test(
    'mensagemPermissao explains the denied-forever case with a settings hint',
    () {
      expect(
        mensagemPermissao(LocationPermissionResult.deniedForever),
        contains('configurações'),
      );
    },
  );

  test('mensagemPermissao explains the disabled-service case', () {
    expect(
      mensagemPermissao(LocationPermissionResult.serviceDisabled),
      contains('localização'),
    );
  });

  test('mensagemPermissao explains the simple-denied case', () {
    expect(
      mensagemPermissao(LocationPermissionResult.denied),
      contains('localização'),
    );
  });

  testWidgets(
    'deniedForever shows an "Abrir configurações" button that opens app settings',
    (tester) async {
      final fakeLocationService = _FakeLocationService(
        LocationPermissionResult.deniedForever,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            locationServiceProvider.overrideWithValue(fakeLocationService),
            professionalsRepositoryProvider.overrideWithValue(
              _buildFakeRepository(),
            ),
          ],
          child: const MaterialApp(home: ProfessionalsSearchScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tentar novamente'), findsOneWidget);
      expect(find.text('Abrir configurações'), findsOneWidget);

      await tester.tap(find.text('Abrir configurações'));
      await tester.pumpAndSettle();

      expect(fakeLocationService.abrirConfiguracoesChamadas, 1);
    },
  );

  testWidgets('typing a name re-runs the search with q after the debounce', (
    tester,
  ) async {
    final queries = <Map<String, dynamic>>[];
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          if (o.path == '/professionals/search') {
            queries.add(Map.of(o.queryParameters));
          }
          h.resolve(Response(requestOptions: o, statusCode: 200, data: []));
        },
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationServiceProvider.overrideWithValue(
            _FakeLocationService(LocationPermissionResult.granted),
          ),
          professionalsRepositoryProvider.overrideWithValue(
            ProfessionalsRepository(dio),
          ),
        ],
        child: const MaterialApp(home: ProfessionalsSearchScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Buscar pelo nome'),
      'Hel',
    );
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect(queries.last['q'], 'Hel');
  });

  testWidgets(
    'simple denied state does not show the "Abrir configurações" button',
    (tester) async {
      final fakeLocationService = _FakeLocationService(
        LocationPermissionResult.denied,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            locationServiceProvider.overrideWithValue(fakeLocationService),
            professionalsRepositoryProvider.overrideWithValue(
              _buildFakeRepository(),
            ),
          ],
          child: const MaterialApp(home: ProfessionalsSearchScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tentar novamente'), findsOneWidget);
      expect(find.text('Abrir configurações'), findsNothing);
    },
  );
}
