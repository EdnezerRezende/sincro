import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_providers.dart';
import '../email_triage/email_triage_providers.dart';
import '../onboarding/anamnese/anamnese_providers.dart';
import '../onboarding/anamnese/anamnese_wizard_screen.dart';
import '../trusted_contacts/trusted_contacts_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _busy = false;

  Future<void> _editSensoryProfile() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AnamneseWizardScreen(isEditing: true)),
    );
  }

  Future<void> _deleteSensoryProfile() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Apagar perfil sensorial?'),
        content: const Text(
          'Suas respostas sobre notificações, gatilhos e tom preferido serão apagadas. '
          'Você pode preenchê-las novamente quando quiser.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Apagar')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(sensoryProfileRepositoryProvider).remove();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perfil sensorial apagado.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível apagar seu perfil sensorial. Tente novamente.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _manageContacts() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TrustedContactsScreen()),
    );
  }

  Future<void> _disconnectGmail() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Desconectar Gmail?'),
        content: const Text(
          'O resumo da sua caixa de entrada será apagado. Você pode reconectar quando quiser.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Desconectar')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(gmailConnectionRepositoryProvider).disconnect();
      ref.invalidate(gmailConnectionStatusProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gmail desconectado.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível desconectar o Gmail. Tente novamente.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    try {
      await ref.read(authServiceProvider).signOut();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível sair. Tente novamente.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Editar perfil sensorial'),
            onTap: _busy ? null : _editSensoryProfile,
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Apagar perfil sensorial'),
            onTap: _busy ? null : _deleteSensoryProfile,
          ),
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: const Text('Gerenciar contatos de confiança'),
            onTap: _busy ? null : _manageContacts,
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('Desconectar Gmail'),
            onTap: _busy ? null : _disconnectGmail,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sair'),
            onTap: _busy ? null : _signOut,
          ),
        ],
      ),
    );
  }
}
