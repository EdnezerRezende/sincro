import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'onboarding_providers.dart';

class OnboardingRouterScreen extends ConsumerWidget {
  const OnboardingRouterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersRepository = ref.watch(usersRepositoryProvider);

    return FutureBuilder(
      future: usersRepository.getMe(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return const Scaffold(body: Center(child: Text('Não foi possível carregar seu perfil.')));
        }
        final status = snapshot.data!;
        if (!status.hasSensoryProfile) {
          return const _RedirectOnce(routeName: '/onboarding/anamnese');
        }
        if (status.trustedContactCount == 0) {
          return const _RedirectOnce(routeName: '/onboarding/contacts');
        }
        return const _RedirectOnce(routeName: '/home');
      },
    );
  }
}

class _RedirectOnce extends StatefulWidget {
  const _RedirectOnce({required this.routeName});

  final String routeName;

  @override
  State<_RedirectOnce> createState() => _RedirectOnceState();
}

class _RedirectOnceState extends State<_RedirectOnce> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacementNamed(widget.routeName);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}
