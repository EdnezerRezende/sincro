import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/app_input.dart';
import 'admin_professional_form_screen.dart';
import 'admin_professionals_filter.dart';
import 'professional.dart';
import 'professionals_providers.dart';

final adminProfessionalsListProvider = FutureProvider.autoDispose<List<Professional>>((ref) {
  return ref.watch(adminProfessionalsRepositoryProvider).list();
});

class AdminProfessionalsListScreen extends ConsumerStatefulWidget {
  const AdminProfessionalsListScreen({super.key});

  @override
  ConsumerState<AdminProfessionalsListScreen> createState() => _AdminProfessionalsListScreenState();
}

class _AdminProfessionalsListScreenState extends ConsumerState<AdminProfessionalsListScreen> {
  String _termo = '';
  bool _mostrarInativos = false;

  Future<void> _desativar(BuildContext context, Professional profissional) async {
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

  Future<void> _reativar(BuildContext context, Professional p) async {
    try {
      await ref.read(adminProfessionalsRepositoryProvider).reactivate(p.id);
      ref.invalidate(adminProfessionalsListProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível reativar. Tente novamente.')));
      }
    }
  }

  Widget _tile(BuildContext context, Professional profissional) {
    return ListTile(
      title: Text(profissional.nome + (profissional.ativo ? '' : ' (inativo)')),
      subtitle: Text(profissional.tags.join(', ')),
      trailing: profissional.ativo
          ? IconButton(
              icon: const Icon(Icons.visibility_off_outlined),
              tooltip: 'Desativar',
              onPressed: () => _desativar(context, profissional),
            )
          : TextButton(onPressed: () => _reativar(context, profissional), child: const Text('Reativar')),
      onTap: () async {
        final saved = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => AdminProfessionalFormScreen(profissional: profissional)),
        );
        if (saved == true) ref.invalidate(adminProfessionalsListProvider);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final professionalsAsync = ref.watch(adminProfessionalsListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profissionais (admin)')),
      body: professionalsAsync.when(
        data: (professionals) {
          final visiveis = filtrarProfissionaisAdmin(professionals, termo: _termo, mostrarInativos: _mostrarInativos);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: AppInput(label: 'Buscar', placeholder: 'Nome, cidade ou tag', onChanged: (v) => setState(() => _termo = v)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(child: Text(resumoContagem(professionals), style: Theme.of(context).textTheme.bodyMedium)),
                    FilterChip(
                      label: const Text('Mostrar inativos'),
                      selected: _mostrarInativos,
                      onSelected: (v) => setState(() => _mostrarInativos = v),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: professionals.isEmpty
                    ? const Center(child: Text('Nenhum profissional cadastrado ainda.'))
                    : visiveis.isEmpty
                        ? const Center(child: Text('Nenhum profissional encontrado por aqui ainda.'))
                        : ListView.builder(itemCount: visiveis.length, itemBuilder: (context, index) => _tile(context, visiveis[index])),
              ),
            ],
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
