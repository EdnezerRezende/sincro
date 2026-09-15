import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/professionals/admin_professionals_filter.dart';
import 'package:sincro_mobile/features/professionals/professional.dart';

Professional _p(String nome, {bool ativo = true, List<String> tags = const [], String cidade = 'SP'}) => Professional(
    id: nome, nome: nome, tags: tags, cidade: cidade, latitude: 0, longitude: 0, telefone: '+5511999999999', bio: '', ativo: ativo);

void main() {
  final todos = [_p('Helena', tags: ['Psicólogo']), _p('Marcos', cidade: 'Guarulhos'), _p('Ana', ativo: false)];

  test('hides inactive by default and searches name, city and tag case-insensitively', () {
    expect(filtrarProfissionaisAdmin(todos, termo: '', mostrarInativos: false).map((p) => p.nome), ['Helena', 'Marcos']);
    expect(filtrarProfissionaisAdmin(todos, termo: 'psic', mostrarInativos: false).map((p) => p.nome), ['Helena']);
    expect(filtrarProfissionaisAdmin(todos, termo: 'guaru', mostrarInativos: false).map((p) => p.nome), ['Marcos']);
    expect(filtrarProfissionaisAdmin(todos, termo: 'ana', mostrarInativos: true).map((p) => p.nome), ['Ana']);
  });

  test('summarises counts with singular/plural', () {
    expect(resumoContagem(todos), '2 ativos · 1 inativo');
    expect(resumoContagem([todos.first]), '1 ativo · 0 inativos');
  });
}
