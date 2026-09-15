import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/widgets/app_button.dart';
import '../trusted_contacts/trusted_contact.dart';
import 'emergency_message.dart';
import 'emergency_providers.dart';
import 'emergency_send_queue.dart';

Future<void> _defaultLaunch(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

Future<void> showEmergencySheet(
  BuildContext context, {
  required List<TrustedContact> contacts,
  Future<void> Function(Uri) launch = _defaultLaunch,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _EmergencySheet(contacts: contacts, launch: launch),
  );
}

class _EmergencySheet extends ConsumerStatefulWidget {
  const _EmergencySheet({required this.contacts, required this.launch});

  final List<TrustedContact> contacts;
  final Future<void> Function(Uri) launch;

  @override
  ConsumerState<_EmergencySheet> createState() => _EmergencySheetState();
}

class _EmergencySheetState extends ConsumerState<_EmergencySheet> {
  late final Set<String> _selected = widget.contacts.map((c) => c.id).toSet();
  late final TextEditingController _template = TextEditingController(text: kEmergencyDefaultTemplate);
  EmergencySendQueue? _queue;
  bool _preparing = false;
  String? _error;

  @override
  void dispose() {
    _template.dispose();
    super.dispose();
  }

  List<TrustedContact> get _selectedContacts =>
      widget.contacts.where((c) => _selected.contains(c.id)).toList();

  Future<void> _start() async {
    setState(() {
      _preparing = true;
      _error = null;
    });
    try {
      final ids = _selectedContacts.map((c) => c.id).toList();
      final template = _template.text.trim();
      final messages = await ref.read(emergencyRepositoryProvider).buildMessages(
            ids,
            template: template == kEmergencyDefaultTemplate ? null : template,
          );
      _queue = EmergencySendQueue(messages);
      await _openCurrent();
    } catch (_) {
      setState(() => _error = 'Não foi possível preparar as mensagens. Tente novamente.');
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  /// Decisão de implementação: a fila avança assim que `launch` retorna (o WhatsApp foi
  /// aberto), sem depender de `AppLifecycleState.resumed` — mais simples e testável, e o
  /// usuário só vê o próximo passo quando voltar ao app de qualquer forma.
  Future<void> _openCurrent() async {
    final queue = _queue!;
    final current = queue.current;
    if (current == null) return;
    try {
      await widget.launch(Uri.parse(current.waUrl));
    } catch (_) {
      if (mounted) setState(() => _error = 'Não foi possível abrir o WhatsApp.');
      return;
    }
    queue.markCurrentOpened();
    if (!mounted) return;
    if (queue.isDone) {
      final n = queue.total;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Avisos abertos para $n ${n == 1 ? 'pessoa' : 'pessoas'}.')),
      );
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final queue = _queue;
    final selectedNames = _selectedContacts.map((c) => primeiroNome(c.nome)).toList();
    final canSend = _selected.isNotEmpty && !_preparing && _template.text.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: scheme.outline, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 12),
            Text('Avisar Rede de Apoio', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text('Escolha quem avisar e ajuste a mensagem, se quiser. Nada é enviado sem você confirmar.',
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            if (queue != null && !queue.isDone) ...[
              Text('Enviado para ${primeiroNome(queue.last!.contactName)}. Próximo: ${primeiroNome(queue.current!.contactName)}',
                  style: theme.textTheme.bodyLarge),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: scheme.error)),
              ],
              const SizedBox(height: 12),
              AppButton(
                label: 'Continuar com ${primeiroNome(queue.current!.contactName)}',
                size: AppButtonSize.large,
                onPressed: _openCurrent,
              ),
            ] else ...[
              Text('Quem avisar', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    for (final contact in widget.contacts)
                      CheckboxListTile(
                        value: _selected.contains(contact.id),
                        onChanged: (v) => setState(() => v == true ? _selected.add(contact.id) : _selected.remove(contact.id)),
                        title: Text(contact.nome),
                        subtitle: Text(contact.relacao),
                        controlAffinity: ListTileControlAffinity.trailing,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text('Mensagem', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _template,
                maxLines: 4,
                maxLength: kEmergencyTemplateMaxLength,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text('$kEmergencyNamePlaceholder vira o nome de cada pessoa',
                        style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _template.text = kEmergencyDefaultTemplate),
                    child: const Text('Restaurar padrão'),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: scheme.error)),
              ],
              const SizedBox(height: 12),
              AppButton(
                label: emergencyCtaLabel(_selected.length, selectedNames),
                size: AppButtonSize.large,
                icon: Icons.chat_outlined,
                isLoading: _preparing,
                onPressed: canSend ? _start : null,
              ),
              AppButton(
                label: 'Agora não',
                variant: AppButtonVariant.text,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
