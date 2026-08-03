import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_providers.dart';
import '../email_triage/email_triage_providers.dart';
import '../financas/finance_connection.dart';
import '../financas/finance_providers.dart';
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

  Future<void> _editDiaRecebimento() async {
    final controller = TextEditingController();
    final result = await showDialog<int?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Dia de recebimento'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'Ex: 5 (dia 5 de cada mês)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, null), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, int.tryParse(controller.text)),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (result < 1 || result > 31) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe um dia entre 1 e 31.')),
        );
      }
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(diaRecebimentoRepositoryProvider).update(result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dia de recebimento salvo.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível salvar. Tente novamente.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnectFinanceConnection(FinanceConnection connection) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Desconectar ${connection.instituicao}?'),
        content: const Text('Os dados dessa conexão serão apagados. Você pode reconectar quando quiser.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Desconectar')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(financeConnectionRepositoryProvider).disconnect(connection.id);
      ref.invalidate(financeConnectionsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${connection.instituicao} desconectado.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível desconectar. Tente novamente.')),
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
    final connectionsAsync = ref.watch(financeConnectionsProvider);
    final financeConnectionTiles = connectionsAsync.maybeWhen(
      data: (connections) => connections
          .map(
            (c) => ListTile(
              leading: const Icon(Icons.account_balance_outlined),
              title: Text('Desconectar ${c.instituicao}'),
              onTap: _busy ? null : () => _disconnectFinanceConnection(c),
            ),
          )
          .toList(),
      orElse: () => <Widget>[],
    );

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
          ListTile(
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('Definir dia de recebimento'),
            onTap: _busy ? null : _editDiaRecebimento,
          ),
          ...financeConnectionTiles,
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
