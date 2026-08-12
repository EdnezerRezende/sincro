import 'package:flutter/material.dart';

/// Design system do Sincro: paleta de baixo contraste/sem vermelho agressivo, "soft dark
/// mode" (grafite, não preto puro) e tipografia acessível — mandato explícito de
/// `docs/App para Autistas_ Finanças e Bem-Estar.pdf`. Widgets Material padrão (Card, AppBar,
/// ListTile, botões, SnackBar) herdam esses tokens automaticamente via `Theme.of(context)`.

/// Tons semânticos que o `ColorScheme` padrão não cobre (paz/confirmação e atenção neutra),
/// usados fora do `ColorScheme` porque não têm um slot Material equivalente — `success` e
/// `caution` são conceitos deste app, não do Material Design.
@immutable
class SincroColors extends ThemeExtension<SincroColors> {
  const SincroColors({required this.success, required this.caution});

  /// Estado de paz/confirmação (ex.: "Saldo suficiente"). Nunca decorativo — só onde algo
  /// realmente está resolvido/tranquilo.
  final Color success;

  /// Atenção neutra, não punitiva (ex.: conta a vencer). Terracota suave — nunca vermelho.
  final Color caution;

  static const light = SincroColors(success: Color(0xFF4B8B67), caution: Color(0xFFB4672E));
  static const dark = SincroColors(success: Color(0xFF8FC5A4), caution: Color(0xFFE3A570));

  @override
  SincroColors copyWith({Color? success, Color? caution}) {
    return SincroColors(success: success ?? this.success, caution: caution ?? this.caution);
  }

  @override
  SincroColors lerp(ThemeExtension<SincroColors>? other, double t) {
    if (other is! SincroColors) return this;
    return SincroColors(
      success: Color.lerp(success, other.success, t)!,
      caution: Color.lerp(caution, other.caution, t)!,
    );
  }
}

const _fontFamily = 'Atkinson Hyperlegible';

const _spacing2 = 8.0;
const _spacing3 = 12.0;
const _spacing4 = 16.0;
// ignore: unused_element
const _spacing6 = 24.0;
// ignore: unused_element
const _spacing8 = 32.0;

const _borderRadius = BorderRadius.all(Radius.circular(16));

ColorScheme _lightScheme() {
  return const ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF3F7268),
    onPrimary: Color(0xFFFFFFFF),
    secondary: Color(0xFF64748B),
    onSecondary: Color(0xFFFFFFFF),
    tertiary: Color(0xFFB4672E),
    onTertiary: Color(0xFFFFFFFF),
    // Mapeado para o tom "destructive" dessaturado do spec — nunca o vermelho puro padrão do
    // Material — assim qualquer widget nativo (SnackBar de erro, etc.) já herda o tom certo.
    error: Color(0xFFA6503A),
    onError: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF2B2B26),
    surfaceContainerHighest: Color(0xFFF0EDE6),
    onSurfaceVariant: Color(0xFF6B6A62),
    outline: Color(0xFFE4DFD5),
  );
}

ColorScheme _darkScheme() {
  return const ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF8FBFAE),
    onPrimary: Color(0xFF16302A),
    secondary: Color(0xFFA8B4C2),
    onSecondary: Color(0xFF1D2530),
    tertiary: Color(0xFFE3A570),
    onTertiary: Color(0xFF3A2410),
    error: Color(0xFFD98872),
    onError: Color(0xFF3A1810),
    // Grafite quente — nunca preto puro (#000000), pedido explícito do spec para evitar
    // "halos" visuais no soft dark mode.
    surface: Color(0xFF2C2A24),
    onSurface: Color(0xFFECE8E0),
    surfaceContainerHighest: Color(0xFF34322B),
    onSurfaceVariant: Color(0xFFB2AEA3),
    outline: Color(0xFF423F37),
  );
}

TextTheme _textTheme(ColorScheme scheme) {
  final base = Typography.material2021(colorScheme: scheme).englishLike.apply(
        fontFamily: _fontFamily,
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      );
  // Corpo em 16sp com line-height generoso (1.5) — legibilidade em vez de densidade.
  return base.copyWith(
    bodyLarge: base.bodyLarge?.copyWith(fontSize: 16, height: 1.5),
    bodyMedium: base.bodyMedium?.copyWith(fontSize: 14, height: 1.5),
    headlineMedium: base.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
  );
}

ThemeData _buildTheme(ColorScheme scheme, SincroColors extension) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.brightness == Brightness.light
        ? const Color(0xFFFAF8F5)
        : const Color(0xFF23221D),
    fontFamily: _fontFamily,
    textTheme: _textTheme(scheme),
    extensions: [extension],
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: _borderRadius),
      margin: EdgeInsets.zero,
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: _spacing4, vertical: _spacing2),
      iconColor: scheme.onSurfaceVariant,
      shape: const RoundedRectangleBorder(borderRadius: _borderRadius),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHighest,
      selectedColor: scheme.primary,
      labelStyle: TextStyle(color: scheme.onSurface, fontFamily: _fontFamily),
      secondaryLabelStyle: TextStyle(color: scheme.onPrimary, fontFamily: _fontFamily),
      side: BorderSide(color: scheme.outline),
      padding: const EdgeInsets.symmetric(horizontal: _spacing3, vertical: _spacing2 / 2),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: _spacing4, vertical: _spacing3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: scheme.secondary),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? scheme.primary : null,
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outline, space: _spacing6),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.onSurface,
      contentTextStyle: TextStyle(color: scheme.surface, fontFamily: _fontFamily),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    // Transições padrão do Material 3 (ZoomPageTransitionsBuilder/Cupertino) já são sutis
    // (150–300ms) — sem necessidade de customizar, evita animação decorativa.
  );
}

final ThemeData sincroLightTheme = _buildTheme(_lightScheme(), SincroColors.light);
final ThemeData sincroDarkTheme = _buildTheme(_darkScheme(), SincroColors.dark);

/// Acesso rápido aos tokens semânticos deste app (`success`/`caution`) a partir de qualquer
/// `BuildContext` — mesmo padrão de `Theme.of(context).colorScheme`.
extension SincroThemeX on BuildContext {
  SincroColors get sincroColors => Theme.of(this).extension<SincroColors>()!;
}
