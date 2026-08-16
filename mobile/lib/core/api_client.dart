import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirebaseTokenInterceptor extends Interceptor {
  FirebaseTokenInterceptor(this._firebaseAuth);

  final FirebaseAuth _firebaseAuth;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final user = _firebaseAuth.currentUser;
    if (user != null) {
      final token = await user.getIdToken();
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}

class ApiClient {
  ApiClient({required this.baseUrl, required FirebaseAuth firebaseAuth})
      : _firebaseAuth = firebaseAuth {
    dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      // 30s de folga para os endpoints que passam por um LLM (rascunhos de
      // e-mail, extração de compromisso, classificação) — sem isso, um
      // travamento de rede ou backend deixaria a UI pendurada indefinidamente
      // em vez de falhar rápido.
      receiveTimeout: const Duration(seconds: 30),
    ));
    dio.interceptors.add(FirebaseTokenInterceptor(_firebaseAuth));
  }

  final String baseUrl;
  final FirebaseAuth _firebaseAuth;
  late final Dio dio;
}
