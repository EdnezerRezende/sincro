import 'package:flutter/material.dart';

/// Border idle (outline variant) contra scaffold `#FAF8F5` (light) / `#1A1F23` (dark).
/// Light: #9C9690 ≈ 2.76:1 contra #FAF8F5. Dark: #66605A ≈ 2.68:1 contra #1A1F23.
const Color _kBorderLight = Color(0xFF9C9690);
const Color _kBorderDark = Color(0xFF66605A);

/// Variantes visuais do botão Sincro: primário, secundário, outline, texto.
/// Cada uma tem semântica visual clara e feedback distinto.
enum AppButtonVariant {
  /// Botão primário: ação principal, cor de destaque (primary do tema).
  /// Elevação/scale em estados interativos.
  primary,

  /// Botão secundário: ação secundária, cor neutra (secondary do tema).
  /// Feedback visual menos agressivo que primary.
  secondary,

  /// Botão outline: ação baixa prioridade, apenas border.
  /// Tinta: secondary/outline.
  outline,

  /// Botão texto: sem background, apenas texto. Ação exploratória ou dismiss.
  /// Subutilizado em favor de outline — mas oferecido para case legítimo (close, skip).
  text,
}

/// Tamanho do botão (altura em dp, que define padding horizontal também).
enum AppButtonSize {
  /// 36 dp height — compacto, para espaços restritos.
  /// Atende 48 dp min touch target com padding genérico.
  small,

  /// 48 dp height — padrão, recomendado para maioria dos casos.
  /// Toque confortável em mobile (48x48 min touch target).
  medium,

  /// 56 dp height — destaque, chamada à ação ou formulário crítico.
  large,
}

/// Botão Sincro reutilizável com feedback visual claro, acessibilidade e dark mode nativo.
///
/// Press state inclui feedback simultâneo de color, elevation e scale (0.95 redução).
/// Animação fluida (150ms) com Curves.easeOut conforme Material Design 3.
///
/// Uso básico:
/// ```dart
/// AppButton(
///   label: 'Enviar',
///   onPressed: () { /* ação */ },
///   variant: AppButtonVariant.primary,
/// )
/// ```
///
/// Com ícone à esquerda:
/// ```dart
/// AppButton(
///   label: 'Guardar',
///   icon: Icons.check,
///   onPressed: () { /* ação */ },
/// )
/// ```
///
/// Loading state:
/// ```dart
/// AppButton(
///   label: 'Processar',
///   isLoading: true,
///   onPressed: () { /* não será acionado */ },
/// )
/// ```
///
/// Desabilitado:
/// ```dart
/// AppButton(
///   label: 'Desabilitado',
///   onPressed: null, // Desabilita o botão
/// )
/// ```
class AppButton extends StatefulWidget {
  /// Texto exibido no botão.
  final String label;

  /// Callback quando o botão é pressionado (null = desabilitado).
  final VoidCallback? onPressed;

  /// Variante visual (primary, secondary, outline, text).
  final AppButtonVariant variant;

  /// Tamanho do botão (small, medium, large).
  final AppButtonSize size;

  /// Ícone exibido (antes do texto por padrão).
  final IconData? icon;

  /// Se true, ícone é exibido após o texto.
  final bool iconAfterLabel;

  /// Se true, exibe spinner de loading e desabilita interação.
  final bool isLoading;

  /// Se true, botão é desabilitado (feedback visual morto).
  /// Alternativa à callback null — mais explícita.
  final bool disabled;

  /// Largura mínima customizada. Se null, usa valor padrão conforme size.
  final double? minWidth;

  /// Callback para semantics/acessibilidade customizada.
  final String? semanticLabel;

  const AppButton({
    Key? key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.medium,
    this.icon,
    this.iconAfterLabel = false,
    this.isLoading = false,
    this.disabled = false,
    this.minWidth,
    this.semanticLabel,
  }) : super(key: key);

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    // Inicializa animação de escala: normal (1.0) → pressionado (0.95)
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!_isDisabled()) {
      _scaleController.forward();
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    _scaleController.reverse();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _scaleController.reverse();
  }

  bool _isDisabled() {
    return widget.disabled ||
        widget.isLoading ||
        widget.onPressed == null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = scheme.brightness == Brightness.light;

    // Determina se está realmente desabilitado (callback null OU disabled=true OU loading=true)
    // para fins de interação (onPressed / Semantics).
    final effectiveDisabled = _isDisabled();
    final effectiveOnPressed = effectiveDisabled ? null : widget.onPressed;

    // Estado visual "desabilitado" (fill apagado): isLoading tem prioridade sobre
    // disabled — um botão em loading continua com o fill da variante (ativo, só
    // ocupado), só usa o fill apagado quando está desabilitado de fato e não está
    // carregando.
    final styleDisabled =
        !widget.isLoading && (widget.disabled || widget.onPressed == null);

    // Dimensões conforme size
    final (double height, double horizontalPadding, double minEffectiveWidth) =
        _sizeValues(widget.size);

    // ButtonStyle customizado por variante
    final buttonStyle = _buildButtonStyle(
      scheme: scheme,
      isLight: isLight,
      variant: widget.variant,
      size: widget.size,
      height: height,
      horizontalPadding: horizontalPadding,
      minWidth: widget.minWidth ?? minEffectiveWidth,
      disabled: styleDisabled,
    );

    // Cores de texto/ícone (loading usa a cor "ativa" da variante, não a apagada)
    final textColor = _textColor(scheme, isLight, widget.variant, styleDisabled);

    // Label com ícone (se aplicável)
    final labelWidget = _buildLabel(
      label: widget.label,
      icon: widget.icon,
      iconAfterLabel: widget.iconAfterLabel,
      isLoading: widget.isLoading,
      textColor: textColor,
      height: height,
    );

    // Botão envolvido em Transform.scale (feedback tátil de press)
    final button = Listener(
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: ElevatedButton(
          onPressed: effectiveOnPressed,
          style: buttonStyle,
          child: labelWidget,
        ),
      ),
    );

    // Wrapper com Semantics para acessibilidade
    return Semantics(
      button: true,
      enabled: !effectiveDisabled,
      label: widget.semanticLabel ?? widget.label,
      child: button,
    );
  }

  /// Calcula altura e padding conforme o tamanho do botão.
  static (double height, double horizontalPadding, double minWidth)
      _sizeValues(AppButtonSize size) {
    return switch (size) {
      AppButtonSize.small => (36.0, 12.0, 36.0),
      AppButtonSize.medium => (48.0, 16.0, 48.0),
      AppButtonSize.large => (56.0, 20.0, 56.0),
    };
  }

  /// Constrói o ButtonStyle base, customizado para variante + estado.
  static ButtonStyle _buildButtonStyle({
    required ColorScheme scheme,
    required bool isLight,
    required AppButtonVariant variant,
    required AppButtonSize size,
    required double height,
    required double horizontalPadding,
    required double minWidth,
    required bool disabled,
  }) {
    // Cores base por variante
    late final Color defaultBgColor;
    late final Color defaultFgColor;
    late final Color? borderColor;
    late final double borderWidth;

    switch (variant) {
      case AppButtonVariant.primary:
        defaultBgColor = scheme.primary;
        defaultFgColor = scheme.onPrimary;
        borderColor = null;
        borderWidth = 0;
        break;

      case AppButtonVariant.secondary:
        defaultBgColor = scheme.secondary;
        defaultFgColor = scheme.onSecondary;
        borderColor = null;
        borderWidth = 0;
        break;

      case AppButtonVariant.outline:
        defaultBgColor = Colors.transparent;
        defaultFgColor = scheme.secondary;
        borderColor = isLight ? _kBorderLight : _kBorderDark;
        borderWidth = 1.5;
        break;

      case AppButtonVariant.text:
        defaultBgColor = Colors.transparent;
        defaultFgColor = scheme.secondary;
        borderColor = null;
        borderWidth = 0;
        break;
    }

    // Cor desabilitada: tom quente mais escuro que o scaffold para garantir contraste
    // real (não apenas opacidade). Light #928C86 ≈ 3.14:1 contra #FAF8F5.
    // Dark #6E6862 ≈ 3.02:1 contra #1A1F23.
    final disabledBgColor =
        isLight ? Color(0xFF928C86) : Color(0xFF6E6862);
    // Foreground sólido para garantir ≥3:1 sobre o fill disabled.
    // Light #3A3630 ≈ 3.93:1 sobre #928C86. Dark #EEEEEE ≈ 4.23:1 sobre #6E6862.
    final disabledFgColor =
        isLight ? const Color(0xFF3A3630) : const Color(0xFFEEEEEE);

    // Feedback em hover/press: elevation ou scale (sutil).
    // Nota: `disabled` aqui já representa o estado visual "desabilitado" — o
    // chamador (`build`) resolve a prioridade isLoading > disabled antes de passar
    // este valor, de forma que loading nunca renderiza com o fill apagado.
    final resolvedBgColor = WidgetStateProperty.resolveWith((states) {
      if (disabled) return disabledBgColor;
      if (states.contains(WidgetState.pressed)) {
        // Press state: queda de luminância de ~28% (observável), canal alternativo
        // além do overlay do ripple.
        return Color.lerp(defaultBgColor, Colors.black, 0.28) ?? defaultBgColor;
      }
      if (states.contains(WidgetState.hovered)) {
        // Hover state: levemente mais claro (ou tint)
        return Color.lerp(defaultBgColor, scheme.surface, 0.08) ?? defaultBgColor;
      }
      return defaultBgColor;
    });

    final resolvedFgColor = WidgetStateProperty.resolveWith((states) {
      if (disabled) return disabledFgColor;
      return defaultFgColor;
    });

    final resolvedElevation = WidgetStateProperty.resolveWith((states) {
      if (disabled) return 0.0;
      if (states.contains(WidgetState.pressed)) return 1.0; // Pressed = leve elevação (canal extra de feedback)
      if (states.contains(WidgetState.hovered)) return 4.0; // Hover = slight lift
      return 0.0; // Default = flat (Material 3 minimal elevation)
    });

    // Para outline/border, precisamos usar OutlinedButton ou customizar manualmente
    late final OutlinedBorder shape;
    if (variant == AppButtonVariant.outline || variant == AppButtonVariant.text) {
      shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side: BorderSide(
          color: borderColor ?? Colors.transparent,
          width: borderWidth,
        ),
      );
    } else {
      shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      );
    }

    // Usar ButtonStyle() diretamente para controle total
    return ButtonStyle(
      backgroundColor: resolvedBgColor,
      foregroundColor: resolvedFgColor,
      elevation: resolvedElevation,
      padding: WidgetStateProperty.all(
        EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: 0,
        ),
      ),
      minimumSize: WidgetStateProperty.all(Size(minWidth, height)),
      maximumSize: WidgetStateProperty.all(Size(double.infinity, height)),
      shape: WidgetStateProperty.all(shape),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) {
          return scheme.onSurface.withValues(alpha: 0.08);
        }
        if (states.contains(WidgetState.pressed)) {
          return scheme.onSurface.withValues(alpha: 0.12);
        }
        return Colors.transparent;
      }),
      splashFactory: InkRipple.splashFactory,
      animationDuration: const Duration(milliseconds: 150),
    );
  }

  /// Determina cor do texto/ícone conforme variante e estado.
  static Color _textColor(
    ColorScheme scheme,
    bool isLight,
    AppButtonVariant variant,
    bool disabled,
  ) {
    if (disabled) {
      // Cores sólidas para ≥3:1 sobre o fill disabled (#928C86 light / #6E6862 dark).
      return isLight ? const Color(0xFF3A3630) : const Color(0xFFEEEEEE);
    }

    return switch (variant) {
      AppButtonVariant.primary => scheme.onPrimary,
      AppButtonVariant.secondary => scheme.onSecondary,
      AppButtonVariant.outline => scheme.secondary,
      AppButtonVariant.text => scheme.secondary,
    };
  }

  /// Constrói o label com ícone + texto + loading spinner.
  static Widget _buildLabel({
    required String label,
    required IconData? icon,
    required bool iconAfterLabel,
    required bool isLoading,
    required Color textColor,
    required double height,
  }) {
    // Ícone size proporcional à altura do botão
    final iconSize = height >= 56 ? 24.0 : (height >= 48 ? 20.0 : 16.0);

    // Se loading, mostra spinner em vez de ícone
    late final Widget? leadingIcon;
    if (isLoading) {
      leadingIcon = SizedBox(
        width: iconSize,
        height: iconSize,
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(textColor),
          strokeWidth: 2.0,
        ),
      );
    } else if (icon != null) {
      leadingIcon = Icon(
        icon,
        size: iconSize,
        color: textColor,
      );
    } else {
      leadingIcon = null;
    }

    // Texto sempre opaco — o spinner já indica o estado de loading.
    final textWidget = Opacity(
      opacity: 1.0,
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: height >= 56 ? 16 : (height >= 48 ? 14 : 12),
        ),
      ),
    );

    // Layout: icon (ou spinner) + texto
    if (leadingIcon == null) {
      return textWidget;
    }

    const spacing = SizedBox(width: 8.0); // Espaçamento entre ícone e texto

    if (iconAfterLabel) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [textWidget, spacing, leadingIcon],
      );
    } else {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [leadingIcon, spacing, textWidget],
      );
    }
  }
}

/// Helper para criar um botão primário com configurações padrão.
/// Útil para ações principais sem verbosidade.
class PrimaryButton extends AppButton {
  const PrimaryButton({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
    AppButtonSize size = AppButtonSize.medium,
    IconData? icon,
    bool isLoading = false,
  }) : super(
    key: key,
    label: label,
    onPressed: onPressed,
    variant: AppButtonVariant.primary,
    size: size,
    icon: icon,
    isLoading: isLoading,
  );
}

/// Helper para criar um botão secundário com configurações padrão.
class SecondaryButton extends AppButton {
  const SecondaryButton({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
    AppButtonSize size = AppButtonSize.medium,
    IconData? icon,
  }) : super(
    key: key,
    label: label,
    onPressed: onPressed,
    variant: AppButtonVariant.secondary,
    size: size,
    icon: icon,
  );
}

/// Helper para criar um botão outline com configurações padrão.
class OutlineButton extends AppButton {
  const OutlineButton({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
    AppButtonSize size = AppButtonSize.medium,
    IconData? icon,
  }) : super(
    key: key,
    label: label,
    onPressed: onPressed,
    variant: AppButtonVariant.outline,
    size: size,
    icon: icon,
  );
}

/// Helper para criar um botão de texto com configurações padrão.
class TextButtonApp extends AppButton {
  const TextButtonApp({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
    AppButtonSize size = AppButtonSize.medium,
    IconData? icon,
  }) : super(
    key: key,
    label: label,
    onPressed: onPressed,
    variant: AppButtonVariant.text,
    size: size,
    icon: icon,
  );
}
