import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/professionals/admin_professionals_list_screen.dart';
import 'package:sincro_mobile/features/professionals/admin_professionals_repository.dart';
import 'package:sincro_mobile/features/professionals/professionals_providers.dart';

void main() {
  testWidgets('shows search field, count and reactivate for inactive when toggled', (tester) async {
    String? patchPath;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      if (o.method == 'PATCH') { patchPath = o.path; h.resolve(Response(requestOptions: o, statusCode: 200, data: {})); return; }
      h.resolve(Response(requestOptions: o, statusCode: 200, data: [
        {'id': 'p1', 'nome': 'Helena', 'tags': ['Psicólogo'], 'cidade': 'SP', 'latitude': 0, 'longitude': 0, 'telefone': '+5511999999999', 'bio': '', 'ativo': true},
        {'id': 'p2', 'nome': 'Ana', 'tags': ['Psicólogo'], 'cidade': 'SP', 'latitude': 0, 'longitude': 0, 'telefone': '+5511999999999', 'bio': '', 'ativo': false},
      ]));
    }));
    await tester.pumpWidget(ProviderScope(
      overrides: [adminProfessionalsRepositoryProvider.overrideWithValue(AdminProfessionalsRepository(dio))],
      child: const MaterialApp(home: AdminProfessionalsListScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('1 ativo · 1 inativo'), findsOneWidget);
    expect(find.text('Ana (inativo)'), findsNothing);

    await tester.tap(find.text('Mostrar inativos'));
    await tester.pumpAndSettle();
    expect(find.text('Ana (inativo)'), findsOneWidget);

    await tester.tap(find.text('Reativar'));
    await tester.pumpAndSettle();
    expect(patchPath, '/admin/professionals/p2');
  });
}
