import 'package:health/health.dart';
import 'health_reading.dart';

class BiofeedbackHealthService {
  final Health _health = Health();

  static const _tipos = [
    HealthDataType.HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_SDNN,
  ];

  Future<bool> solicitarPermissao() async {
    return _health.requestAuthorization(
      _tipos,
      permissions: _tipos.map((_) => HealthDataAccess.READ).toList(),
    );
  }

  Future<List<HealthReading>> lerFrequenciaCardiacaHoje() {
    return _lerTipoHoje(HealthDataType.HEART_RATE);
  }

  Future<List<HealthReading>> lerVariabilidadeHoje() {
    return _lerTipoHoje(HealthDataType.HEART_RATE_VARIABILITY_SDNN);
  }

  Future<List<HealthReading>> _lerTipoHoje(HealthDataType tipo) async {
    final agora = DateTime.now();
    final inicioDoDia = DateTime(agora.year, agora.month, agora.day);
    final pontos = await _health.getHealthDataFromTypes(
      types: [tipo],
      startTime: inicioDoDia,
      endTime: agora,
    );
    return pontos
        .map(
          (p) => HealthReading(
            valor: (p.value as NumericHealthValue).numericValue.toDouble(),
            timestamp: p.dateFrom,
          ),
        )
        .toList();
  }
}
