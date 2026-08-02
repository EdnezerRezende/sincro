import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_providers.dart';
import 'trusted_contact.dart';
import 'trusted_contacts_repository.dart';

final trustedContactsRepositoryProvider = Provider<TrustedContactsRepository>((ref) {
  return TrustedContactsRepository(ref.watch(apiClientProvider).dio);
});

final trustedContactsListProvider = FutureProvider.autoDispose<List<TrustedContact>>((ref) {
  return ref.watch(trustedContactsRepositoryProvider).list();
});
