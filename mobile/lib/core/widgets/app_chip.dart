import 'package:flutter/material.dart';

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
      // Disabled: morto visualmente (opacidade reduzida)
      backgroundColor =
          isLight ? Color(0xFFF0EDE6) : Color(0xFF34322B);
      foregroundColor = scheme.onSurface.withValues(alpha: 0.4);
      borderColor = scheme.outline.withValues(alpha: 0.4);
      borderWidth = 0;
    } else if (selected) {
      // Selected: cor/background claro (não ambíguo)
      backgroundColor = scheme.primary;
      foregroundColor = scheme.onPrimary;
      borderColor = scheme.primary;
      borderWidth = 0;
    } else {
      // Default: outline ou cor pálida, visualmente distinto de selected
      switch (variant) {
        case AppChipVariant.input:
          // Input default: fundo leve com outline
          backgroundColor = isLight ? Color(0xFFF0EDE6) : Color(0xFF34322B);
          foregroundColor = scheme.onSurface;
          borderColor = scheme.outline;
          borderWidth = 1.0;
          break;

        case AppChipVariant.suggestion:
          // Suggestion default: fundo mais leve, sugestivo
          backgroundColor = isLight ? Color(0xFFFAF8F5) : Color(0xFF2C2A24);
          foregroundColor = scheme.onSurfaceVariant;
          borderColor = scheme.outline;
          borderWidth = 1.0;
          break;

        case AppChipVariant.filter:
          // Filter default: outline style, sem fundo opaco
          backgroundColor = scheme.surface;
          foregroundColor = scheme.onSurface;
          borderColor = scheme.outline;
          borderWidth = 1.0;
          break;
      }
    }

    // Opacity reduzida para disabled
    final opacity = enabled ? 1.0 : 0.6;

    // Construir widget — usar FilterChip para melhor suporte nativo a seleção
    final chip = ConstrainedBox(
      constraints: BoxConstraints(minHeight: 36.0),
      child: FilterChip(
        label: _ChipLabel(
          text: label,
          icon: icon,
          iconAfterLabel: iconAfterLabel,
          textStyle: labelStyle ??
              (Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: foregroundColor,
                    fontWeight: FontWeight.w500,
                  ) ??
                  TextStyle(color: foregroundColor)),
          iconColor: foregroundColor,
        ),
        selected: selected,
        onSelected: enabled ? onSelected : null,
        backgroundColor: backgroundColor,
        selectedColor: backgroundColor,
        disabledColor: backgroundColor,
        side: BorderSide(color: borderColor, width: borderWidth),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.0), // 36 dp height → 18 dp radius
        ),
        padding: effectivePadding,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        showCheckmark: false, // Evitar checkmark padrão — feedback é via cor/background
        labelPadding: EdgeInsets.zero, // Label manage padding internally
        elevation: 0,
        pressElevation: 0,
      ),
    );

    return Opacity(
      opacity: opacity,
      child: chip,
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
