import 'package:flutter/material.dart';
import 'emergency_button.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sincro')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const [
            Text('🌿 Tudo em ordem por hoje.'),
            SizedBox(height: 8),
            Text('Finanças e e-mails chegam em breve.'),
            SizedBox(height: 32),
            EmergencyButton(),
          ],
        ),
      ),
    );
  }
}
