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
    dio = Dio(BaseOptions(baseUrl: baseUrl));
    dio.interceptors.add(FirebaseTokenInterceptor(_firebaseAuth));
  }

  final String baseUrl;
  final FirebaseAuth _firebaseAuth;
  late final Dio dio;
}
