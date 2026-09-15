import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/widgets/app_button.dart';
import '../trusted_contacts/trusted_contacts_providers.dart';
import 'professional.dart';
import 'relacao_from_tags.dart';

String buildWhatsAppUrl(String telefone) {
  final digits = telefone.replaceAll(RegExp(r'[^0-9]'), '');
  return 'https://wa.me/$digits';
}

String buildTelUrl(String telefone) {
  final digits = telefone.replaceAll(RegExp(r'[^0-9+]'), '');
  return 'tel:$digits';
}

class ProfessionalDetailScreen extends ConsumerStatefulWidget {
  const ProfessionalDetailScreen({super.key, required this.profissional});

  final Professional profissional;

  @override
  ConsumerState<ProfessionalDetailScreen> createState() => _ProfessionalDetailScreenState();
}

class _ProfessionalDetailScreenState extends ConsumerState<ProfessionalDetailScreen> {
  bool _adicionando = false;

  Future<void> _abrirWhatsApp(BuildContext context) async {
    try {
      await launchUrl(Uri.parse(buildWhatsAppUrl(widget.profissional.telefone)), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir o WhatsApp.')),
        );
      }
    }
  }

  Future<void> _ligar(BuildContext context) async {
    try {
      await launchUrl(Uri.parse(buildTelUrl(widget.profissional.telefone)));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir o discador.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.profissional.nome)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(spacing: 8, children: widget.profissional.tags.map((tag) => Chip(label: Text(tag))).toList()),
            const SizedBox(height: 12),
            Text(widget.profissional.cidade),
            const SizedBox(height: 12),
            Text(widget.profissional.bio),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _abrirWhatsApp(context),
              icon: const Icon(Icons.chat_outlined),
              label: const Text('Abrir WhatsApp'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _ligar(context),
              icon: const Icon(Icons.call_outlined),
              label: const Text('Ligar'),
            ),
            const SizedBox(height: 24),
            Text(
              'Ao adicionar, a pessoa passa a aparecer em Rede de apoio e pode receber seu aviso de emergência.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            _buildAdicionarButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildAdicionarButton(BuildContext context) {
    final telefoneOk = telefoneValidoParaContato(widget.profissional.telefone);
    final contatosAsync = ref.watch(trustedContactsListProvider);
    final jaExiste = contatosAsync.maybeWhen(
      data: (c) => c.any((x) => normalizarTelefone(x.whatsapp) == normalizarTelefone(widget.profissional.telefone)),
      orElse: () => false,
    );
    if (jaExiste) {
      return const AppButton(label: 'Já está na sua rede de apoio', size: AppButtonSize.large, icon: Icons.check, onPressed: null);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          label: _adicionando ? 'Adicionando…' : 'Adicionar à rede de apoio',
          size: AppButtonSize.large,
          icon: Icons.favorite_outline,
          isLoading: _adicionando,
          onPressed: telefoneOk && !_adicionando ? () => _abrirDialogo(context) : null,
        ),
        if (!telefoneOk)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Telefone do profissional em formato inválido.', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
      ],
    );
  }

  Future<void> _abrirDialogo(BuildContext context) async {
    var relacao = relacaoFromTags(widget.profissional.tags);
    var consentimento = false;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Adicionar à rede de apoio'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                // `value:` está deprecado no Flutter 3.47 (gera warning no analyze); com
                // `initialValue` o campo guarda o próprio estado e `onChanged` só registra a escolha.
                initialValue: relacao,
                decoration: const InputDecoration(labelText: 'Relação'),
                items: const ['PSICOLOGO', 'PSIQUIATRA', 'T.O.', 'FAMILIAR', 'OUTRO']
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) => relacao = v ?? relacao,
              ),
              CheckboxListTile(
                value: consentimento,
                onChanged: (v) => setDialogState(() => consentimento = v ?? false),
                title: const Text(
                  'Você autoriza o Sincro a preparar mensagens de alerta para este contato em momentos de crise. Você sempre confirma antes do envio.',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: consentimento ? () => Navigator.pop(dialogContext, true) : null, child: const Text('Adicionar')),
          ],
        ),
      ),
    );
    if (confirmado != true || !mounted) return;

    setState(() => _adicionando = true);
    try {
      await ref.read(trustedContactsRepositoryProvider).create(
            nome: widget.profissional.nome,
            relacao: relacao,
            whatsapp: normalizarTelefone(widget.profissional.telefone),
            prioridade: 0,
            consentimentoAceito: true,
          );
      ref.invalidate(trustedContactsListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Adicionado à sua rede de apoio.')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível adicionar. Tente novamente.')));
      }
    } finally {
      if (mounted) setState(() => _adicionando = false);
    }
  }
}
