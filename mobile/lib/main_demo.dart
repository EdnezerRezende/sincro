import 'package:flutter/material.dart';
import 'core/widgets/app_button_demo.dart';
import 'core/theme.dart';

void main() {
  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AppButton Demo',
      theme: sincroLightTheme,
      darkTheme: sincroDarkTheme,
      themeMode: ThemeMode.system,
      home: const AppButtonDemo(),
    );
  }
}
