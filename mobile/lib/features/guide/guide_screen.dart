import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'guide_content.dart';
import 'guide_item.dart';
import 'guide_providers.dart';

class GuideScreen extends ConsumerWidget {
  const GuideScreen({super.key, required this.items, required this.title});

  final List<GuideItem> items;
  final String title;

  Future<void> _fechar(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(guidePreferenceProvider).setVersaoVista(guiaVersaoAtual);
    } catch (_) {
      // Best-effort — mesmo padrão de outras preferências locais deste app: uma falha de
      // persistência não deve impedir o usuário de fechar a tela (ver spec, "Erros e casos
      // de borda").
    } finally {
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              children: items.map((item) {
                return ListTile(
                  leading: Icon(item.icon),
                  title: Text(item.title),
                  subtitle: Text(item.description),
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _fechar(context, ref),
                child: const Text('Entendi'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
