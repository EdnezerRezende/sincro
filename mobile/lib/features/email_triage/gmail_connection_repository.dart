import 'package:dio/dio.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GmailConnectionStatus {
  const GmailConnectionStatus({
    required this.connected,
    this.gmailEmail,
    this.temEscopoEnvio = false,
    this.temEscopoAgenda = false,
    this.temEscopoModificacao = false,
  });

  final bool connected;
  final String? gmailEmail;
  final bool temEscopoEnvio;
  final bool temEscopoAgenda;
  // gmail.modify: precisa ser concedido para arquivar/excluir e-mails pelo app. Contas que
  // conectaram o Gmail antes desse escopo existir vêm com este campo em `false` até reconectar.
  final bool temEscopoModificacao;

  factory GmailConnectionStatus.fromJson(Map<String, dynamic> json) {
    return GmailConnectionStatus(
      connected: json['connected'] as bool,
      gmailEmail: json['gmailEmail'] as String?,
      temEscopoEnvio: json['temEscopoEnvio'] as bool? ?? false,
      temEscopoAgenda: json['temEscopoAgenda'] as bool? ?? false,
      temEscopoModificacao: json['temEscopoModificacao'] as bool? ?? false,
    );
  }
}

class GmailConnectionRepository {
  GmailConnectionRepository(this._dio, this._googleSignInFactory);

  final Dio _dio;

  // Constrói o GoogleSignIn sob demanda: no web, `GoogleSignIn()` dispara a inicialização do
  // plugin (`initWithParams`) assim que é instanciado. Se este repositório recebesse a instância
  // já pronta (como antes), o simples fato de ler `gmailConnectionRepositoryProvider` — o que
  // acontece toda vez que `gmailConnectionStatusProvider` é observado, inclusive na Home, sem
  // nenhuma intenção de usar o Google Sign-In — já construiria o GoogleSignIn e dispararia essa
  // inicialização, que lança uma exceção não tratada quando não há client ID do Google
  // configurado (ver google_sign_in_web `initWithParams`, linha `clientId: appClientId!`). Adiar
  // a construção para o primeiro uso real (connect/disconnect) evita esse gatilho inteiramente.
  final GoogleSignIn Function() _googleSignInFactory;
  GoogleSignIn? _googleSignIn;
  GoogleSignIn get _googleSignInInstance => _googleSignIn ??= _googleSignInFactory();

  Future<void> connect() async {
    final account = await _googleSignInInstance.signIn();
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
    await _googleSignInInstance.signOut();
  }
}
