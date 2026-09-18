// Cobre o `EmailSummariesNotifier` isoladamente (sem árvore de widgets): `build` sempre busca a
// primeira página; `carregarMais` concatena a página seguinte e atualiza o cursor, é no-op sem
// cursor (ou com uma busca já em andamento) e reverte só a flag `carregandoMais` em caso de erro,
// preservando os itens já carregados; `recarregar` descarta o cache e refaz a busca do zero.
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/email_triage/email_summary.dart';
import 'package:sincro_mobile/features/email_triage/email_summary_repository.dart';
import 'package:sincro_mobile/features/email_triage/email_triage_providers.dart';

EmailSummary _summary(String id) => EmailSummary(
  id: id,
  remetente: 'Banco <banco@example.com>',
  assunto: 'Fatura $id',
  resumoCurto: 'Resumo $id',
  categoria: 'PODE_ESPERAR',
  recebidoEm: DateTime.utc(2026, 9, 16, 12),
);

final _s1 = _summary('s1');
final _s2 = _summary('s2');
final _s3 = _summary('s3');

/// Fake que devolve páginas pré-programadas, na ordem em que `listar` é chamado (a primeira
/// chamada é sempre o `build`, sem cursor; chamadas seguintes vêm de `carregarMais`, com cursor).
/// `Dio()` passado ao `super` nunca chega a ser usado: `listar` é sobrescrito antes de qualquer
/// requisição real acontecer.
class _FakeRepo extends EmailSummaryRepository {
  _FakeRepo({required this.paginas}) : super(Dio());

  final List<PaginaResumos> paginas;
  int chamadasListar = 0;
  final List<String?> cursoresRecebidos = [];

  @override
  Future<PaginaResumos> listar({String? cursor, int limite = 50}) async {
    cursoresRecebidos.add(cursor);
    final indice = chamadasListar.clamp(0, paginas.length - 1);
    chamadasListar++;
    return paginas[indice];
  }
}

/// Fake cuja segunda chamada (a de `carregarMais`, feita com cursor) sempre falha — usado para
/// provar que o erro não descarta os itens já carregados.
class _FakeRepoComErroNaSegundaPagina extends EmailSummaryRepository {
  _FakeRepoComErroNaSegundaPagina() : super(Dio());

  @override
  Future<PaginaResumos> listar({String? cursor, int limite = 50}) async {
    if (cursor == null) {
      return const PaginaResumos(itens: [], proximoCursor: 'c1');
    }
    throw DioException(requestOptions: RequestOptions(path: '/resumos-email'));
  }
}

void main() {
  test('build carrega a página 1 e expõe o cursor devolvido pelo backend', () async {
    final repo = _FakeRepo(
      paginas: [PaginaResumos(itens: [_s1, _s2], proximoCursor: 'c1')],
    );
    final container = ProviderContainer(
      overrides: [emailSummaryRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    final estado = await container.read(emailSummariesProvider.future);

    expect(estado.itens.map((s) => s.id), ['s1', 's2']);
    expect(estado.proximoCursor, 'c1');
    expect(estado.carregandoMais, false);
    expect(repo.cursoresRecebidos, [null]);
  });

  test(
    'carregarMais concatena a página seguinte, atualiza o cursor, e é no-op sem cursor',
    () async {
      final repo = _FakeRepo(
        paginas: [
          PaginaResumos(itens: [_s1, _s2], proximoCursor: 'c1'),
          PaginaResumos(itens: [_s3], proximoCursor: null),
        ],
      );
      final container = ProviderContainer(
        overrides: [emailSummaryRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      // `listen` mantém o provider vivo (é `autoDispose`) durante todo o teste.
      final sub = container.listen(emailSummariesProvider, (_, _) {});
      addTearDown(sub.close);

      final primeira = await container.read(emailSummariesProvider.future);
      expect(primeira.itens.map((s) => s.id), ['s1', 's2']);

      await container.read(emailSummariesProvider.notifier).carregarMais();
      final segunda = container.read(emailSummariesProvider).requireValue;
      expect(segunda.itens.map((s) => s.id), ['s1', 's2', 's3']);
      expect(segunda.proximoCursor, isNull);
      expect(repo.cursoresRecebidos, [null, 'c1']);

      // `proximoCursor` agora é `null` — chamar de novo não deve gerar uma nova requisição.
      await container.read(emailSummariesProvider.notifier).carregarMais();
      expect(repo.chamadasListar, 2);
      final terceira = container.read(emailSummariesProvider).requireValue;
      expect(terceira.itens.map((s) => s.id), ['s1', 's2', 's3']);
    },
  );

  test('carregarMais em erro reverte carregandoMais e preserva os itens já carregados', () async {
    final repo = _FakeRepoComErroNaSegundaPagina();
    final container = ProviderContainer(
      overrides: [emailSummaryRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final sub = container.listen(emailSummariesProvider, (_, _) {});
    addTearDown(sub.close);

    final primeira = await container.read(emailSummariesProvider.future);
    expect(primeira.itens, isEmpty);
    expect(primeira.proximoCursor, 'c1');

    await container.read(emailSummariesProvider.notifier).carregarMais();

    final depoisDoErro = container.read(emailSummariesProvider).requireValue;
    expect(depoisDoErro.itens, isEmpty);
    // O cursor não some com o erro: uma nova tentativa de "Carregar mais" continua possível.
    expect(depoisDoErro.proximoCursor, 'c1');
    expect(depoisDoErro.carregandoMais, false);
  });

  test('recarregar descarta o estado atual e refaz a busca da página 1', () async {
    final repo = _FakeRepo(
      paginas: [
        PaginaResumos(itens: [_s1], proximoCursor: 'c1'),
        PaginaResumos(itens: [_s1, _s2], proximoCursor: null),
      ],
    );
    final container = ProviderContainer(
      overrides: [emailSummaryRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final sub = container.listen(emailSummariesProvider, (_, _) {});
    addTearDown(sub.close);

    final primeira = await container.read(emailSummariesProvider.future);
    expect(primeira.itens.map((s) => s.id), ['s1']);

    await container.read(emailSummariesProvider.notifier).recarregar();

    final segunda = container.read(emailSummariesProvider).requireValue;
    expect(segunda.itens.map((s) => s.id), ['s1', 's2']);
    expect(segunda.proximoCursor, isNull);
    expect(repo.chamadasListar, 2);
    // `recarregar` sempre busca do zero, nunca manda o cursor da página anterior.
    expect(repo.cursoresRecebidos, [null, null]);
  });
}
