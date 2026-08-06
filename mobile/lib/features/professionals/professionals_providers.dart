import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_providers.dart';
import 'location_service.dart';
import 'professionals_repository.dart';

final professionalsRepositoryProvider = Provider<ProfessionalsRepository>((ref) {
  return ProfessionalsRepository(ref.watch(apiClientProvider).dio);
});

final professionalTagsProvider = FutureProvider.autoDispose<List<String>>((ref) {
  return ref.watch(professionalsRepositoryProvider).listTags();
});

final locationServiceProvider = Provider<LocationService>((ref) => LocationService());
