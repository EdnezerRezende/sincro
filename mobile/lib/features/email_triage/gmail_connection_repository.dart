import 'package:dio/dio.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GmailConnectionStatus {
  const GmailConnectionStatus({
    required this.connected,
    this.gmailEmail,
    this.temEscopoEnvio = false,
    this.temEscopoAgenda = false,
  });

  final bool connected;
  final String? gmailEmail;
  final bool temEscopoEnvio;
  final bool temEscopoAgenda;

  factory GmailConnectionStatus.fromJson(Map<String, dynamic> json) {
    return GmailConnectionStatus(
      connected: json['connected'] as bool,
      gmailEmail: json['gmailEmail'] as String?,
      temEscopoEnvio: json['temEscopoEnvio'] as bool? ?? false,
      temEscopoAgenda: json['temEscopoAgenda'] as bool? ?? false,
    );
  }
}

class GmailConnectionRepository {
  GmailConnectionRepository(this._dio, this._googleSignIn);

  final Dio _dio;
  final GoogleSignIn _googleSignIn;

  Future<void> connect() async {
    final account = await _googleSignIn.signIn();
    if (account == null) {
      throw Exception('Login com Google cancelado.');
    }
    final serverAuthCode = account.serverAuthCode;
    if (serverAuthCode == null) {
      throw Exception('Não foi possível obter autorização do Google para acessar o Gmail.');
    }
    await _dio.post('/gmail/connect', data: {'serverAuthCode': serverAuthCode});
  }

  Future<GmailConnectionStatus> status() async {
    final response = await _dio.get('/gmail/connection');
    return GmailConnectionStatus.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> disconnect() async {
    await _dio.delete('/gmail/connection');
    await _googleSignIn.signOut();
  }
}
