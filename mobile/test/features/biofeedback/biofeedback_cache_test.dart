import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_cache.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_summary.dart';
import 'package:sincro_mobile/features/biofeedback/dia_repouso.dart';
import 'package:sincro_mobile/features/biofeedback/estado_estresse.dart';

void main() {
  // `BiofeedbackCache` usa `SharedPreferencesAsync` (ver o comentário lá sobre isolates), que
  // exige um backend de plataforma registrado; nos testes usamos o backend em memória oficial.
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = null;
  });

  test('isAtivo defaults to false when nothing was ever saved', () async {
    final cache = BiofeedbackCache();

    expect(await cache.isAtivo(), false);
  });

  test('setAtivo persists the flag for later reads', () async {
    final cache = BiofeedbackCache();

    await cache.setAtivo(true);

    expect(await cache.isAtivo(), true);
  });

  test('getFrequenciaMinutos defaults to 30 when nothing was ever saved', () async {
    final cache = BiofeedbackCache();

    expect(await cache.getFrequenciaMinutos(), 30);
  });

  test('setFrequenciaMinutos persists the chosen value', () async {
    final cache = BiofeedbackCache();

    await cache.setFrequenciaMinutos(60);

    expect(await cache.getFrequenciaMinutos(), 60);
  });

  test('getResumo returns null when nothing was ever saved', () async {
    final cache = BiofeedbackCache();

    expect(await cache.getResumo(), isNull);
  });

  test('setResumo then getResumo round-trips the summary', () async {
    final cache = BiofeedbackCache();
    final resumo = BiofeedbackSummary(
      ultimaFc: 72,
      mediaFcHoje: 70,
      mediaVfcHoje: 45,
      estadoEstresse: EstadoEstresse.coletandoDados,
      atualizadoEm: DateTime.utc(2026, 8, 3, 14, 0),
    );

    await cache.setResumo(resumo);
    final lido = await cache.getResumo();

    expect(lido?.ultimaFc, 72);
    expect(lido?.atualizadoEm, DateTime.utc(2026, 8, 3, 14, 0));
  });

  test('clear removes ativo, frequencia, and resumo together', () async {
    final cache = BiofeedbackCache();
    await cache.setAtivo(true);
    await cache.setFrequenciaMinutos(60);
    await cache.setResumo(BiofeedbackSummary(
      ultimaFc: 72,
      mediaFcHoje: 70,
      mediaVfcHoje: 45,
      estadoEstresse: EstadoEstresse.coletandoDados,
      atualizadoEm: DateTime.utc(2026, 8, 3, 14, 0),
    ));

    await cache.clear();

    expect(await cache.isAtivo(), false);
    expect(await cache.getFrequenciaMinutos(), 30);
    expect(await cache.getResumo(), isNull);
  });

  test('getHistoricoRepouso returns an empty list when nothing was ever saved', () async {
    final cache = BiofeedbackCache();

    expect(await cache.getHistoricoRepouso(), isEmpty);
  });

  test('setHistoricoRepouso then getHistoricoRepouso round-trips the list', () async {
    final cache = BiofeedbackCache();
    final historico = [
      DiaRepouso(data: DateTime.utc(2026, 8, 1), mediaFcRepouso: 68, mediaVfcRepouso: 44),
      DiaRepouso(data: DateTime.utc(2026, 8, 2), mediaFcRepouso: 70, mediaVfcRepouso: 45),
    ];

    await cache.setHistoricoRepouso(historico);
    final lido = await cache.getHistoricoRepouso();

    expect(lido, hasLength(2));
    expect(lido[0].data, DateTime.utc(2026, 8, 1));
    expect(lido[1].mediaFcRepouso, 70);
  });

  test('getPermissoesVersao defaults to 0 when nothing was ever saved', () async {
    final cache = BiofeedbackCache();

    // Quem ativou o Biofeedback na Fase 1 nunca gravou esta chave — o 0 é justamente o que
    // sinaliza "concedeu só as permissões antigas" e dispara o pedido das novas.
    expect(await cache.getPermissoesVersao(), 0);
  });

  test('setPermissoesVersao persists the recorded version', () async {
    final cache = BiofeedbackCache();

    await cache.setPermissoesVersao(BiofeedbackCache.versaoPermissoesAtual);

    expect(await cache.getPermissoesVersao(), BiofeedbackCache.versaoPermissoesAtual);
  });

  test('clear also removes the permissoes versao', () async {
    final cache = BiofeedbackCache();
    await cache.setPermissoesVersao(BiofeedbackCache.versaoPermissoesAtual);

    await cache.clear();

    expect(await cache.getPermissoesVersao(), 0);
  });

  test('clear also removes the historico de repouso', () async {
    final cache = BiofeedbackCache();
    await cache.setHistoricoRepouso([
      DiaRepouso(data: DateTime.utc(2026, 8, 1), mediaFcRepouso: 68, mediaVfcRepouso: 44),
    ]);

    await cache.clear();

    expect(await cache.getHistoricoRepouso(), isEmpty);
  });
}
