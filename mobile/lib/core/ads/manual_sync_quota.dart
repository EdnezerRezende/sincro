import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _chaveDia = 'manual_sync_quota_dia';
const _chaveUsadas = 'manual_sync_quota_usadas';
const _chaveDesbloqueioAte = 'manual_sync_quota_desbloqueio_ate';

/// Cota diária de sincronizações manuais do plano gratuito, com desbloqueio temporário ganho ao
/// assistir um anúncio premiado.
///
/// Preferência local (mesmo padrão de `GuidePreference`): é um incentivo de UX, não uma regra de
/// segurança — o backend continua aceitando a sincronização. Se um dia o limite virar regra de
/// negócio (ex.: custo de LLM por sincronização), mova a contagem para o backend e valide a
/// recompensa com SSV (Server-Side Verification) do AdMob.
class ManualSyncQuota {
  ManualSyncQuota({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  late final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  String _hoje() {
    final agora = _clock();
    return '${agora.year}-${agora.month}-${agora.day}';
  }

  Future<DateTime?> desbloqueadoAte() async {
    final millis = await _prefs.getInt(_chaveDesbloqueioAte);
    if (millis == null) return null;
    final ate = DateTime.fromMillisecondsSinceEpoch(millis);
    return ate.isAfter(_clock()) ? ate : null;
  }

  Future<int> usadasHoje() async {
    if (await _prefs.getString(_chaveDia) != _hoje()) return 0;
    return await _prefs.getInt(_chaveUsadas) ?? 0;
  }

  /// Tenta consumir uma sincronização. `limite == null` (ilimitado) ou desbloqueio ativo sempre
  /// permitem; senão, permite enquanto a cota do dia não acabou.
  Future<bool> tentarConsumir(int? limite) async {
    if (limite == null || await desbloqueadoAte() != null) return true;
    final usadas = await usadasHoje();
    if (usadas >= limite) return false;
    await _prefs.setString(_chaveDia, _hoje());
    await _prefs.setInt(_chaveUsadas, usadas + 1);
    return true;
  }

  Future<void> desbloquear(Duration duracao) {
    return _prefs.setInt(_chaveDesbloqueioAte, _clock().add(duracao).millisecondsSinceEpoch);
  }
}

final manualSyncQuotaProvider = Provider<ManualSyncQuota>((ref) => ManualSyncQuota());
