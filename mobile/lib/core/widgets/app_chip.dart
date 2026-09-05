import 'package:flutter/material.dart';

/// Border idle contra scaffold `#FAF8F5` (light) / `#1A1F23` (dark).
/// Light: #9C9690 ≈ 2.76:1 contra #FAF8F5. Dark: #66605A ≈ 2.68:1 contra #1A1F23.
const Color _kBorderLight = Color(0xFF9C9690);
const Color _kBorderDark = Color(0xFF66605A);

/// Disabled fill contra scaffold `#FAF8F5` (light) / `#1A1F23` (dark).
/// Light: #928C86 ≈ 3.14:1 contra #FAF8F5. Dark: #6E6862 ≈ 3.02:1 contra #1A1F23.
const Color _kDisabledBgLight = Color(0xFF928C86);
const Color _kDisabledBgDark = Color(0xFF6E6862);

/// Variantes do chip Sincro: input (selecionável), suggestion (recomendação), filter (toggle).
/// Estados: default, selected, disabled. Acessível, com spacing generoso e feedback visual claro.
enum AppChipVariant {
  /// Chip selecionável para entrada de dados (ex.: anamnese wizard).
  input,

  /// Chip de recomendação — sugestão soft de valor/ação.
  suggestion,

  /// Chip de filtro — toggle, para refinar listagens.
  filter,
}

/// Chip Sincro com 3 variantes, 3 estados (default/selected/disabled), altura ~36 dp,
/// padding 12 dp horizontal, ícone opcional, sem truncamento de texto (quebra se necessário),
/// feedback visual claro (cor, background) e dark mode nativo.
///
/// Uso:
/// ```dart
/// AppChip(
///   label: 'Diabetes',
///   selected: isDiabetic,
///   onSelected: (val) { setState(() { isDiabetic = val; }); },
///   variant: AppChipVariant.input,
/// )
/// ```
class AppChip extends StatelessWidget {
  final String label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final AppChipVariant variant;
  final IconData? icon;
  final bool iconAfterLabel;
  final bool enabled;
  final EdgeInsets? padding;
  final TextStyle? labelStyle;

  const AppChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onSelected,
    this.variant = AppChipVariant.input,
    this.icon,
    this.iconAfterLabel = false,
    this.enabled = true,
    this.padding,
    this.labelStyle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = scheme.brightness == Brightness.light;

    // Padding padrão: 12 dp horizontal, 8 dp vertical (height ~36 dp = 8 dp * 2 + 20 dp text)
    final effectivePadding = padding ??
        const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0);

    // Estados visuais baseados na variante e estado
    late final Color backgroundColor;
    late final Color foregroundColor;
    late final Color borderColor;
    late final double borderWidth;

    if (!enabled) {
      // Disabled: fill com contraste real (≥2.5:1) contra o scaffold.
      // Foreground escuro/claro fixo para dar ≥3:1 sobre o fill disabled
      // (scheme.onSurface.withAlpha(0.4) mediria apenas ~1.1:1 sobre #928C86).
      backgroundColor = isLight ? _kDisabledBgLight : _kDisabledBgDark;
      foregroundColor = isLight
          ? const Color(0xFF3A3630) // ~6:1 sobre #928C86
          : const Color(0xFFEEEEEE); // ~5:1 sobre #6E6862
      borderColor = Colors.transparent;
      borderWidth = 0;
    } else if (selected) {
      // Selected: cor/background claro (não ambíguo)
      backgroundColor = scheme.primary;
      foregroundColor = scheme.onPrimary;
      borderColor = scheme.primary;
      borderWidth = 0;
    } else {
      // Default: outline ou cor pálida, visualmente distinto de selected.
      // Border idle usa _kBorderLight/_kBorderDark em vez de scheme.outline —
      // scheme.outline (#E0E0E0 light / #4A4A4A dark) rende quase invisível
      // contra o scaffold (~1.25:1 / ~1.87:1).
      final idleBorderColor = isLight ? _kBorderLight : _kBorderDark;
      switch (variant) {
        case AppChipVariant.input:
          // Input default: fundo leve com outline
          backgroundColor = isLight ? Color(0xFFF0EDE6) : Color(0xFF34322B);
          foregroundColor = scheme.onSurface;
          borderColor = idleBorderColor;
          borderWidth = 1.0;
          break;

        case AppChipVariant.suggestion:
          // Suggestion default: fundo levemente destacado do scaffold (o fill em si
          // não precisa de contraste — o que importa é a borda ser visível).
          backgroundColor = isLight ? Color(0xFFEAE5DC) : Color(0xFF2C2A24);
          foregroundColor = scheme.onSurfaceVariant;
          borderColor = idleBorderColor;
          borderWidth = 1.0;
          break;

        case AppChipVariant.filter:
          // Filter default: outline style, sem fundo opaco
          backgroundColor = scheme.surface;
          foregroundColor = scheme.onSurface;
          borderColor = idleBorderColor;
          borderWidth = 1.0;
          break;
      }
    }

    final effectiveLabelStyle = labelStyle ??
        (Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w500,
            ) ??
            TextStyle(color: foregroundColor));

    final labelWidget = _ChipLabel(
      text: label,
      icon: icon,
      iconAfterLabel: iconAfterLabel,
      textStyle: effectiveLabelStyle,
      iconColor: foregroundColor,
    );

    // Widget custom em vez de FilterChip para evitar a camada _kDisabledAlpha (38%)
    // que o RawChip aplica ao label quando onSelected == null — isso tornava labels
    // ilegíveis mesmo quando enabled == true e o chip era apenas informativo.
    final effectiveBorderRadius = BorderRadius.circular(20.0);
    final shape = RoundedRectangleBorder(
      borderRadius: effectiveBorderRadius,
      side: BorderSide(color: borderColor, width: borderWidth),
    );

    return Semantics(
      button: enabled && onSelected != null,
      checked: selected,
      enabled: enabled,
      label: label,
      child: Material(
        color: backgroundColor,
        shape: shape,
        child: InkWell(
          onTap: (enabled && onSelected != null)
              ? () => onSelected!(!selected)
              : null,
          borderRadius: effectiveBorderRadius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36.0, minWidth: 0),
            child: Padding(
              padding: effectivePadding,
              child: labelWidget,
            ),
          ),
        ),
      ),
    );
  }
}

/// Label interno do chip — gerencia layout de texto + ícone sem truncamento.
class _ChipLabel extends StatelessWidget {
  final String text;
  final IconData? icon;
  final bool iconAfterLabel;
  final TextStyle textStyle;
  final Color iconColor;

  const _ChipLabel({
    required this.text,
    this.icon,
    this.iconAfterLabel = false,
    required this.textStyle,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final iconWidget = icon != null
        ? Icon(
            icon,
            size: 18.0, // Ícone compacto (18 dp)
            color: iconColor,
          )
        : null;

    final textWidget = Text(
      text,
      style: textStyle,
      maxLines: 2, // Quebra até 2 linhas em vez de truncar
      overflow: TextOverflow.clip, // Sem elipsis — quebra visual
    );

    // Espaçamento 8 dp entre ícone e texto
    const spacing = SizedBox(width: 8.0);

    if (iconWidget == null) {
      return textWidget;
    }

    if (iconAfterLabel) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [textWidget, spacing, iconWidget],
      );
    } else {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [iconWidget, spacing, textWidget],
      );
    }
  }
}

/// Wrapper para exibir múltiplos chips com spacing consistente (gap >= 8 dp).
/// Quebra automaticamente para linhas subsequentes (Wrap).
class AppChipGroup extends StatelessWidget {
  final List<AppChip> chips;
  final double spacing;
  final double runSpacing;
  final WrapAlignment alignment;

  const AppChipGroup({
    super.key,
    required this.chips,
    this.spacing = 8.0,
    this.runSpacing = 8.0,
    this.alignment = WrapAlignment.start,
  })  : assert(spacing >= 8.0);

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: spacing,
      runSpacing: runSpacing,
      alignment: alignment,
      children: chips,
    );
  }
}
