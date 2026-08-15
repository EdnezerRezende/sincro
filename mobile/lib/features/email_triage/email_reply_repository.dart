import 'package:dio/dio.dart';
import 'compromisso_sugerido.dart';
import 'rascunhos_email.dart';

class EnvioResultado {
  const EnvioResultado({required this.enviado, this.compromissoSugerido});

  final bool enviado;
  final CompromissoSugerido? compromissoSugerido;

  factory EnvioResultado.fromJson(Map<String, dynamic> json) {
    final compromisso = json['compromissoSugerido'];
    return EnvioResultado(
      enviado: json['enviado'] as bool,
      compromissoSugerido:
          compromisso == null ? null : CompromissoSugerido.fromJson(compromisso as Map<String, dynamic>),
    );
  }
}

class EmailReplyRepository {
  EmailReplyRepository(this._dio);

  final Dio _dio;

  Future<RascunhosEmail> gerarRascunhos(String emailId) async {
    final response = await _dio.post('/resumos-email/$emailId/rascunhos');
    return RascunhosEmail.fromJson(response.data as Map<String, dynamic>);
  }

  Future<EnvioResultado> enviar(String emailId, String texto) async {
    final response = await _dio.post('/resumos-email/$emailId/enviar', data: {'texto': texto});
    return EnvioResultado.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> confirmarCompromisso(CompromissoSugerido compromisso) async {
    await _dio.post('/resumos-email/compromissos/confirmar', data: compromisso.toJson());
  }
}
