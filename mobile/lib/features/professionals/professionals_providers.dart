import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_providers.dart';
import 'admin_professionals_repository.dart';
import 'location_service.dart';
import 'professionals_repository.dart';

final professionalsRepositoryProvider = Provider<ProfessionalsRepository>((ref) {
  return ProfessionalsRepository(ref.watch(apiClientProvider).dio);
});

final adminProfessionalsRepositoryProvider = Provider<AdminProfessionalsRepository>((ref) {
  return AdminProfessionalsRepository(ref.watch(apiClientProvider).dio);
});

final professionalTagsProvider = FutureProvider.autoDispose<List<String>>((ref) {
  return ref.watch(professionalsRepositoryProvider).listTags();
});

final locationServiceProvider = Provider<LocationService>((ref) => LocationService());
