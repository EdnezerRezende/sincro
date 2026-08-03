import 'package:dio/dio.dart';

class DiaRecebimentoRepository {
  DiaRecebimentoRepository(this._dio);

  final Dio _dio;

  Future<void> update(int? diaRecebimento) async {
    await _dio.patch('/users/me/dia-recebimento', data: {'diaRecebimento': diaRecebimento});
  }
}
