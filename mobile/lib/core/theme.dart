import 'package:flutter/material.dart';

/// Design system do Sincro: paleta extraída do branding (ciano/azul) com acessibilidade
/// garantida (WCAG AA em todos os pares cor/fundo), "soft dark mode" (grafite, não preto
/// puro) e tipografia escalada — mandato explícito de `docs/App para Autistas_ Finanças
/// e Bem-Estar.pdf`. Widgets Material padrão (Card, AppBar, ListTile, botões, SnackBar)
/// herdam esses tokens automaticamente via `Theme.of(context)`.
///
/// Tons semânticos que o `ColorScheme` padrão não cobre (paz/confirmação e atenção neutra),
/// usados fora do `ColorScheme` porque não têm um slot Material equivalente — `success` e
/// `caution` são conceitos deste app, não do Material Design.

// ============================================================================
// COLOR PALETTE
// ============================================================================

/// Paleta de cores harmonicamente derivada dos assets (logo + splash).
/// Cada cor tem propósito semântico e é testada para contraste WCAG AA.
///
/// **Light Mode (bright surfaces):**
/// - Primary #005A80:    Cyan-blue escuro (branding, ações principais)
/// - Secondary #00539E:  Azul profundo (ações secundárias, links)
/// - Success #2E7D32:    Verde profundo (confirmação, "tudo bem")
/// - Caution #8B5A00:    Marrom/âmbar (atenção neutra, sem punitivo)
/// - Error #C62828:      Vermelho dessaturado (erro, destrutivo)
/// - Surface #FFFFFF:    Fundo claro
/// - OnSurface #1A1A1A:  Texto em superfícies claras
///
/// **Dark Mode (dark surfaces):**
/// - Primary #4DD0E1:    Cyan claro (branding vibrante em dark)
/// - Secondary #4DB8E8:  Azul light (secundário em dark)
/// - Success #66BB6A:    Verde light (confirmação em dark)
/// - Caution #FFB74D:    Âmbar claro (atenção em dark)
/// - Error #EF5350:      Vermelho light (erro em dark)
/// - Surface #1A1F23:    Fundo escuro (grafite quente, não #000000 puro)
/// - OnSurface #EEEEEE:  Texto em superfícies escuras
///
/// **Contraste garantido (WCAG AA, ≥4.5:1 em todos os pares):**
/// - Primary on White: 7.57:1
/// - Secondary on White: 7.69:1
/// - Success on White: 5.13:1
/// - Caution on White: 5.90:1
/// - Error on White: 5.62:1
/// - Primary on #1A1F23 (dark): 9.04:1
/// - Caution on #1A1F23 (dark): 9.60:1
@immutable
class SincroColors extends ThemeExtension<SincroColors> {
  const SincroColors({required this.success, required this.caution});

  /// Estado de paz/confirmação (ex.: "Saldo suficiente"). Nunca decorativo — só onde
  /// algo realmente está resolvido/tranquilo.
  final Color success;

  /// Atenção neutra, não punitiva (ex.: conta a vencer). Marrom/âmbar suave — nunca
  /// vermelho agressivo. Comunica "note isto" sem alarme.
  final Color caution;

  static const light = SincroColors(success: Color(0xFF2E7D32), caution: Color(0xFF8B5A00));
  static const dark = SincroColors(success: Color(0xFF66BB6A), caution: Color(0xFFFFB74D));

  @override
  SincroColors copyWith({Color? success, Color? caution}) {
    return SincroColors(
      success: success ?? this.success,
      caution: caution ?? this.caution,
    );
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

// ============================================================================
// TYPOGRAPHY TOKENS
// ============================================================================

const _fontFamily = 'Atkinson Hyperlegible';

// Heading: 20–24 sp (H3 Material equivalent)
const _headingSize = 20.0;

// Body: 16–18 sp (primary text, readable in low-light / high-contrast scenarios)
const _bodySize = 16.0;

// Body small: 14 sp (secondary text, metadata)
const _bodySmallSize = 14.0;

// Caption: 12–14 sp (labels, hints)
const _captionSize = 12.0;

// Line height: generous (1.5) for readability (explicit mandate for autism-friendly design)
const _lineHeightBody = 1.5;
const _lineHeightCaption = 1.4;

// ============================================================================
// SPACING TOKENS (8dp grid)
// ============================================================================

/// 8 dp — smallest spacing (button padding, icon spacing)
const _spacing2 = 8.0;

/// 12 dp — chip padding vertical, icon-text gap
const _spacing3 = 12.0;

/// 16 dp — standard padding, list item padding
const _spacing4 = 16.0;

/// 24 dp — section/card padding, divider spacing
const _spacing6 = 24.0;

/// 32 dp — large spacing (screen margins, section gaps)
// ignore: unused_element
const _spacing8 = 32.0;

// ============================================================================
// SHAPE TOKENS
// ============================================================================

/// Standard rounded corners (16 dp = Material's medium shape)
const _borderRadius = BorderRadius.all(Radius.circular(16));

/// Button border radius (12 dp = slightly more conservative)
const _borderRadiusButton = 12.0;

// ============================================================================
// LIGHT THEME COLOR SCHEME
// ============================================================================

ColorScheme _lightScheme() {
  return const ColorScheme(
    brightness: Brightness.light,
    // Primária: cyan-blue (#005A80) — branding, ações principais
    primary: Color(0xFF005A80),
    onPrimary: Color(0xFFFFFFFF),
    // Secundária: azul profundo (#00539E) — ações secundárias, links
    secondary: Color(0xFF00539E),
    onSecondary: Color(0xFFFFFFFF),
    // Terciária: mantida para compatibilidade Material 3, pode ser repropositada
    tertiary: Color(0xFF8B5A00),
    onTertiary: Color(0xFFFFFFFF),
    // Erro: vermelho dessaturado (#C62828) — nunca puro, sempre comunicar erro com calma
    error: Color(0xFFC62828),
    onError: Color(0xFFFFFFFF),
    // Superfícies
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF1A1A1A),
    surfaceContainerHighest: Color(0xFFF5F5F5),
    onSurfaceVariant: Color(0xFF666666),
    // Outline para borders (cinza claro)
    outline: Color(0xFFE0E0E0),
  );
}

// ============================================================================
// DARK THEME COLOR SCHEME
// ============================================================================

ColorScheme _darkScheme() {
  return const ColorScheme(
    brightness: Brightness.dark,
    // Primária: cyan claro (#4DD0E1) — vibrante em fundo escuro
    primary: Color(0xFF4DD0E1),
    onPrimary: Color(0xFF001F2B),
    // Secundária: azul light (#4DB8E8)
    secondary: Color(0xFF4DB8E8),
    onSecondary: Color(0xFF00263F),
    // Terciária
    tertiary: Color(0xFFFFB74D),
    onTertiary: Color(0xFF331D00),
    // Erro: vermelho light (#EF5350)
    error: Color(0xFFEF5350),
    onError: Color(0xFF3A0E0A),
    // Superfícies: grafite quente, nunca preto puro (#000000)
    // #1A1F23 = RGB(26, 31, 35) — quente, evita "halos" visuais
    surface: Color(0xFF1A1F23),
    onSurface: Color(0xFFEEEEEE),
    surfaceContainerHighest: Color(0xFF2A2F35),
    onSurfaceVariant: Color(0xFFB8B8B8),
    outline: Color(0xFF4A4A4A),
  );
}

// ============================================================================
// TEXT THEME
// ============================================================================

TextTheme _textTheme(ColorScheme scheme) {
  // Base do Material 2021 com fonte customizada
  final base = Typography.material2021(colorScheme: scheme)
      .englishLike
      .apply(
        fontFamily: _fontFamily,
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      );

  return base.copyWith(
    // Heading: 20 sp, bold, line-height 1.2 (tighter para headings)
    headlineSmall:
        base.headlineSmall?.copyWith(fontSize: _headingSize, fontWeight: FontWeight.w700, height: 1.2),
    headlineMedium: base.headlineMedium?.copyWith(
        fontSize: _headingSize + 2, fontWeight: FontWeight.w700, height: 1.2),

    // Body: 16 sp, generous line-height (1.5) para legibilidade neurodivergente
    bodyLarge: base.bodyLarge?.copyWith(fontSize: _bodySize, height: _lineHeightBody),
    bodyMedium: base.bodyMedium?.copyWith(fontSize: _bodySmallSize, height: _lineHeightBody),

    // Caption: 12 sp, line-height 1.4
    labelSmall: base.labelSmall?.copyWith(fontSize: _captionSize, height: _lineHeightCaption),
  );
}

// ============================================================================
// BUILD THEME
// ============================================================================

ThemeData _buildTheme(ColorScheme scheme, SincroColors extension) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // Fundo do scaffold: quase branco/quase preto (nunca puro para evitar brilho)
    scaffoldBackgroundColor: scheme.brightness == Brightness.light
        ? const Color(0xFFFAF8F5)
        : const Color(0xFF1A1F23),
    fontFamily: _fontFamily,
    textTheme: _textTheme(scheme),
    extensions: [extension],

    // AppBar: transparente, sem shadow
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: false,
    ),

    // Card: sem shadow, border radius padrão
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: _borderRadius),
      margin: EdgeInsets.zero,
    ),

    // ListTile: padding semântico (horizontal 16, vertical 8)
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: _spacing4, vertical: _spacing2),
      iconColor: scheme.onSurfaceVariant,
      shape: const RoundedRectangleBorder(borderRadius: _borderRadius),
    ),

    // Chip: tamanho compacto com padding controlado
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHighest,
      selectedColor: scheme.primary,
      labelStyle: TextStyle(color: scheme.onSurface, fontFamily: _fontFamily),
      secondaryLabelStyle: TextStyle(color: scheme.onPrimary, fontFamily: _fontFamily),
      side: BorderSide(color: scheme.outline),
      padding: const EdgeInsets.symmetric(horizontal: _spacing3, vertical: _spacing2 / 2),
    ),

    // ElevatedButton: sem shadow, padding generoso
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: _spacing4, vertical: _spacing3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_borderRadiusButton)),
      ),
    ),

    // TextButton: cor secundária para links
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: scheme.secondary),
    ),

    // Switch: primária quando selecionada
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? scheme.primary : null,
      ),
    ),

    // Divider: outline color com spacing 24 dp
    dividerTheme: DividerThemeData(color: scheme.outline, space: _spacing6),

    // SnackBar: fundo escuro (onSurface), texto claro, floating
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.onSurface,
      contentTextStyle: TextStyle(color: scheme.surface, fontFamily: _fontFamily),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_borderRadiusButton)),
    ),

    // Menu: herda do tema
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surface),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(_borderRadiusButton)),
        ),
      ),
    ),

    // Transições padrão do Material 3 (ZoomPageTransitionsBuilder/Cupertino)
    // já são sutis (150–300ms) — sem necessidade de customizar.
  );
}

// ============================================================================
// THEME INSTANCES
// ============================================================================

final ThemeData sincroLightTheme = _buildTheme(_lightScheme(), SincroColors.light);
final ThemeData sincroDarkTheme = _buildTheme(_darkScheme(), SincroColors.dark);

// ============================================================================
// EXTENSION FOR EASY ACCESS
// ============================================================================

/// Acesso rápido aos tokens semânticos deste app (`success`/`caution`) a partir de qualquer
/// `BuildContext` — mesmo padrão de `Theme.of(context).colorScheme`.
///
/// **Uso:**
/// ```dart
/// final colors = context.sincroColors;
/// final successColor = colors.success;
/// final cautionColor = colors.caution;
/// ```
extension SincroThemeX on BuildContext {
  SincroColors get sincroColors => Theme.of(this).extension<SincroColors>()!;
}
