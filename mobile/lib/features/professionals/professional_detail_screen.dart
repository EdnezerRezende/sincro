import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'professional.dart';

String buildWhatsAppUrl(String telefone) {
  final digits = telefone.replaceAll(RegExp(r'[^0-9]'), '');
  return 'https://wa.me/$digits';
}

String buildTelUrl(String telefone) {
  final digits = telefone.replaceAll(RegExp(r'[^0-9+]'), '');
  return 'tel:$digits';
}

class ProfessionalDetailScreen extends StatelessWidget {
  const ProfessionalDetailScreen({super.key, required this.profissional});

  final Professional profissional;

  Future<void> _abrirWhatsApp(BuildContext context) async {
    try {
      await launchUrl(Uri.parse(buildWhatsAppUrl(profissional.telefone)), mode: LaunchMode.externalApplication);
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
      await launchUrl(Uri.parse(buildTelUrl(profissional.telefone)));
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
      appBar: AppBar(title: Text(profissional.nome)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(spacing: 8, children: profissional.tags.map((tag) => Chip(label: Text(tag))).toList()),
            const SizedBox(height: 12),
            Text(profissional.cidade),
            const SizedBox(height: 12),
            Text(profissional.bio),
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
          ],
        ),
      ),
    );
  }
}
