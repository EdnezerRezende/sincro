import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'admin_professional_form_screen.dart';
import 'professional.dart';
import 'professionals_providers.dart';

final adminProfessionalsListProvider = FutureProvider.autoDispose<List<Professional>>((ref) {
  return ref.watch(adminProfessionalsRepositoryProvider).list();
});

class AdminProfessionalsListScreen extends ConsumerWidget {
  const AdminProfessionalsListScreen({super.key});

  Future<void> _desativar(BuildContext context, WidgetRef ref, Professional profissional) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Desativar profissional?'),
        content: Text('${profissional.nome} deixará de aparecer nas buscas dos usuários.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Desativar')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(adminProfessionalsRepositoryProvider).deactivate(profissional.id);
      ref.invalidate(adminProfessionalsListProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível desativar. Tente novamente.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final professionalsAsync = ref.watch(adminProfessionalsListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profissionais (admin)')),
      body: professionalsAsync.when(
        data: (professionals) {
          if (professionals.isEmpty) {
            return const Center(child: Text('Nenhum profissional cadastrado ainda.'));
          }
          return ListView.builder(
            itemCount: professionals.length,
            itemBuilder: (context, index) {
              final profissional = professionals[index];
              return ListTile(
                title: Text(profissional.nome + (profissional.ativo ? '' : ' (inativo)')),
                subtitle: Text(profissional.tags.join(', ')),
                trailing: profissional.ativo
                    ? IconButton(
                        icon: const Icon(Icons.visibility_off_outlined),
                        tooltip: 'Desativar',
                        onPressed: () => _desativar(context, ref, profissional),
                      )
                    : null,
                onTap: () async {
                  final saved = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(builder: (_) => AdminProfessionalFormScreen(profissional: profissional)),
                  );
                  if (saved == true) ref.invalidate(adminProfessionalsListProvider);
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Não foi possível carregar os profissionais.')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Novo profissional'),
        onPressed: () async {
          final saved = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const AdminProfessionalFormScreen()),
          );
          if (saved == true) ref.invalidate(adminProfessionalsListProvider);
        },
      ),
    );
  }
}
