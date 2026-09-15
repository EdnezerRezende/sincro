import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../emergency/emergency_sheet.dart';
import '../trusted_contacts/trusted_contacts_providers.dart';

class EmergencyButton extends ConsumerWidget {
  const EmergencyButton({super.key});

  Future<void> _handlePress(BuildContext context, WidgetRef ref) async {
    try {
      final contacts = await ref.read(trustedContactsRepositoryProvider).list();
      if (!context.mounted) return;
      if (contacts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cadastre um contato de confiança primeiro.')),
        );
        return;
      }
      await showEmergencySheet(context, contacts: contacts);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao preparar mensagem. Tente novamente.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Barra de largura cheia e 56 dp (prancha Home·A): o CTA de emergência precisa ser o alvo
    // mais fácil da tela, não um botão centralizado com metade da largura.
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
      onPressed: () => _handlePress(context, ref),
      icon: const Icon(Icons.favorite),
      label: const Text('Avisar Rede de Apoio'),
    );
  }
}
