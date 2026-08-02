import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_providers.dart';
import '../auth/auth_providers.dart';
import 'onboarding_status.dart';
import 'users_repository.dart';

final usersRepositoryProvider = Provider<UsersRepository>((ref) {
  return UsersRepository(ref.watch(apiClientProvider).dio);
});

/// Fetches the current user's onboarding status.
///
/// Defensive fallback: if `GET /users/me` fails (e.g. 404 because no
/// `usuarios` row exists yet - a reinstall, or a user created directly in
/// the Firebase console), this creates the row with a best-effort name and
/// retries the fetch once before giving up.
final onboardingStatusProvider = FutureProvider.autoDispose<OnboardingStatus>((ref) async {
  final usersRepository = ref.watch(usersRepositoryProvider);
  try {
    return await usersRepository.getMe();
  } catch (_) {
    final authService = ref.read(authServiceProvider);
    final displayName = authService.currentUser?.displayName?.trim();
    final fallbackNome = (displayName != null && displayName.isNotEmpty) ? displayName : 'Usuário Sincro';
    await usersRepository.upsertMe(fallbackNome);
    return usersRepository.getMe();
  }
});
