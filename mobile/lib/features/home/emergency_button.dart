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
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao preparar mensagem: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton.icon(
      onPressed: () => _handlePress(context, ref),
      icon: const Icon(Icons.favorite),
      label: const Text('Avisar Rede de Apoio'),
    );
  }
}
