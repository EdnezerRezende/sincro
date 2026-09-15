import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sem isso, o Flutter test usa um "test font" de fallback com métricas muito
/// mais largas que qualquer fonte real, o que faz textos de CTA (curtos em um
/// dispositivo real) estourarem o `Row` do `AppButton` só dentro do ambiente de
/// teste, na largura real de telefone (390dp) usada por `emergency_sheet_test.dart`.
/// Carregar uma fonte real sob o nome "Roboto" (família default do Material
/// quando nenhuma é especificada) resolve as métricas para algo realista.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fontData = await rootBundle.load('assets/fonts/AtkinsonHyperlegible-Regular.ttf');
  final fontLoader = FontLoader('Roboto')..addFont(Future.value(fontData));
  await fontLoader.load();
  await testMain();
}
