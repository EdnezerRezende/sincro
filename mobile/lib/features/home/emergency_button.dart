import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../emergency/emergency_providers.dart';
import '../trusted_contacts/trusted_contacts_providers.dart';

class EmergencyButton extends ConsumerWidget {
  const EmergencyButton({super.key});

  Future<void> _handlePress(BuildContext context, WidgetRef ref) async {
    try {
      final contacts = await ref.read(trustedContactsRepositoryProvider).list();
      if (contacts.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cadastre um contato de confiança primeiro.')),
          );
        }
        return;
      }

      final priorityContact = contacts.first;
      final message = await ref.read(emergencyRepositoryProvider).buildMessage(priorityContact.id);

      if (!context.mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Avisar ${message.contactName}?'),
          content: Text(message.message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Agora não')),
            ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Abrir WhatsApp')),
          ],
        ),
      );

      if (confirmed == true) {
        await launchUrl(Uri.parse(message.waUrl), mode: LaunchMode.externalApplication);
      }
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
