import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'trusted_contacts_providers.dart';

const _relacoes = ['PSICOLOGO', 'PSIQUIATRA', 'T.O.', 'FAMILIAR', 'OUTRO'];

class AddContactScreen extends ConsumerStatefulWidget {
  const AddContactScreen({super.key});

  @override
  ConsumerState<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends ConsumerState<AddContactScreen> {
  final _nomeController = TextEditingController();
  final _whatsappController = TextEditingController();
  String _relacao = _relacoes.first;
  bool _consentimentoAceito = false;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final repository = ref.read(trustedContactsRepositoryProvider);
    await repository.create(
      nome: _nomeController.text.trim(),
      relacao: _relacao,
      whatsapp: _whatsappController.text.trim(),
      prioridade: 0,
      consentimentoAceito: _consentimentoAceito,
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _nomeController.text.trim().isNotEmpty &&
        _whatsappController.text.trim().isNotEmpty &&
        _consentimentoAceito &&
        !_saving;

    return Scaffold(
      appBar: AppBar(title: const Text('Adicionar contato de confiança')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nomeController,
              decoration: const InputDecoration(labelText: 'Nome'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _relacao,
              items: _relacoes.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
              onChanged: (value) => setState(() => _relacao = value!),
              decoration: const InputDecoration(labelText: 'Relação'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _whatsappController,
              decoration: const InputDecoration(labelText: 'WhatsApp'),
              keyboardType: TextInputType.phone,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _consentimentoAceito,
              onChanged: (value) => setState(() => _consentimentoAceito = value ?? false),
              title: const Text(
                'Você autoriza o Sincro a preparar mensagens de alerta para este contato em momentos de crise. Você sempre confirma antes do envio.',
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: canSave ? _save : null,
              child: _saving ? const CircularProgressIndicator() : const Text('Salvar contato'),
            ),
          ],
        ),
      ),
    );
  }
}
