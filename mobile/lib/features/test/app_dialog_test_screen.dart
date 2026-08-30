import 'package:flutter/material.dart';
import '../../core/widgets/app_dialog.dart';

class AppDialogTestScreen extends StatelessWidget {
  const AppDialogTestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AppDialog Test')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                showAppDialog(
                  context,
                  title: 'Confirmar ação',
                  content: 'Tem certeza que deseja deletar este item? Esta ação não pode ser desfeita.',
                  actions: [
                    DialogAction(
                      label: 'Cancelar',
                      onPressed: () {},
                      type: 'secondary',
                    ),
                    DialogAction(
                      label: 'Deletar',
                      onPressed: () { print('Deletado!'); },
                      type: 'destructive',
                    ),
                  ],
                );
              },
              child: const Text('Show Dialog (Light)'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                showAppDialog(
                  context,
                  title: 'Confirmação',
                  content: 'Este é um conteúdo mais longo para testar se o modal faz scroll corretamente quando necessário. Lorem ipsum dolor sit amet.',
                  actions: [
                    DialogAction(
                      label: 'Não',
                      onPressed: () {},
                      type: 'secondary',
                    ),
                    DialogAction(
                      label: 'Sim',
                      onPressed: () {},
                      type: 'primary',
                    ),
                  ],
                );
              },
              child: const Text('Show Dialog (Long Content)'),
            ),
          ],
        ),
      ),
    );
  }
}
