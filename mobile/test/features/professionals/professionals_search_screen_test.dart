import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/professionals/location_service.dart';
import 'package:sincro_mobile/features/professionals/professionals_search_screen.dart';

void main() {
  test('mensagemPermissao is empty when permission is granted', () {
    expect(mensagemPermissao(LocationPermissionResult.granted), '');
  });

  test('mensagemPermissao explains the denied-forever case with a settings hint', () {
    expect(mensagemPermissao(LocationPermissionResult.deniedForever), contains('configurações'));
  });

  test('mensagemPermissao explains the disabled-service case', () {
    expect(mensagemPermissao(LocationPermissionResult.serviceDisabled), contains('localização'));
  });

  test('mensagemPermissao explains the simple-denied case', () {
    expect(mensagemPermissao(LocationPermissionResult.denied), contains('localização'));
  });
}
