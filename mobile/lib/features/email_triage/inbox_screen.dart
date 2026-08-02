import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'email_summary.dart';
import 'email_triage_providers.dart';

class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summariesAsync = ref.watch(emailSummariesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Caixa de Entrada')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(emailSummariesProvider),
        child: summariesAsync.when(
          data: (summaries) {
            if (summaries.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Nenhum e-mail novo por aqui. 🌿'),
                  ),
                ],
              );
            }
            final precisamAtencao = summaries.where((s) => s.precisaAtencao).toList();
            final podemEsperar = summaries.where((s) => !s.precisaAtencao).toList();

            return ListView(
              children: [
                if (precisamAtencao.isNotEmpty) ...[
                  const _SectionHeader('Precisam de atenção'),
                  ...precisamAtencao.map((s) => _EmailTile(summary: s)),
                ],
                if (podemEsperar.isNotEmpty) ...[
                  const _SectionHeader('Podem esperar'),
                  ...podemEsperar.map((s) => _EmailTile(summary: s)),
                ],
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => ListView(
            children: const [
              Padding(
                padding: EdgeInsets.all(24),
                child: Text('Não foi possível carregar seus e-mails. Puxe para tentar novamente.'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _EmailTile extends StatelessWidget {
  const _EmailTile({required this.summary});

  final EmailSummary summary;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(summary.precisaAtencao ? Icons.priority_high : Icons.check_circle_outline),
      title: Text(summary.assunto),
      subtitle: Text(summary.resumoCurto),
    );
  }
}
