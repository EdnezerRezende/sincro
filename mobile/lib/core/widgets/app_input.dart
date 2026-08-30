import 'package:flutter/material.dart';

/// Tipo de ícone auxiliar no input (sufixo).
enum AppInputSuffixIcon {
  /// Ícone para limpar o conteúdo (X).
  clear,

  /// Ícone para mostrar/ocultar senha (olho).
  showPassword,

  /// Ícone de informação (i).
  info,

  /// Nenhum ícone.
  none,
}

/// Input text reutilizável do Sincro com estados claros (default, focused, filled, error, disabled),
/// label sempre visível (acima do field), placeholder informativo, error message clara abaixo,
/// ícone de helper (clear, show-password, info), altura mínima 48 dp, sem truncagem de texto,
/// suporte a dark mode e acessibilidade (Atkinson Hyperlegible, contrast WCAG AA).
///
/// **Estados visuais:**
/// - **Default**: border cinza claro, label cinza opaco, placeholder visível e opaco.
/// - **Focused**: border + shadow em cor primária, label escuro, fundo com tint sutil.
/// - **Filled**: border cinza, label escuro, placeholder desaparece, texto legível.
/// - **Error**: border vermelha, label + icon vermelhos, error message clara abaixo.
/// - **Disabled**: background morto (cinza), texto com opacidade reduzida, desabilitado ao toque.
///
/// **Tamanho:**
/// - Altura mínima 48 dp (padding 12 dp vertical + 24 dp text).
/// - Largura: fill disponível via parent (Expanded, SizedBox, etc).
/// - Sem truncagem: texto quebra ou wraps sensatamente.
///
/// **Uso básico:**
/// ```dart
/// AppInput(
///   label: 'Email',
///   placeholder: 'seu@email.com',
///   onChanged: (value) { },
/// )
/// ```
///
/// **Com validação:**
/// ```dart
/// AppInput(
///   label: 'Senha',
///   placeholder: 'Mínimo 8 caracteres',
///   obscureText: true,
///   suffixIcon: AppInputSuffixIcon.showPassword,
///   error: 'Senha muito curta',
///   onChanged: (value) { },
/// )
/// ```
///
/// **Com ícone clear:**
/// ```dart
/// AppInput(
///   label: 'Buscar',
///   placeholder: 'Digite...',
///   suffixIcon: AppInputSuffixIcon.clear,
///   onSuffixIconPressed: () { controller.clear(); },
/// )
/// ```
class AppInput extends StatefulWidget {
  /// Rótulo sempre visível acima do field.
  final String label;

  /// Placeholder cinza/opaco dentro do field (não substitui label).
  final String? placeholder;

  /// Texto de erro exibido abaixo do field (desativa o input se não nulo).
  final String? error;

  /// Texto de dica auxiliar abaixo do field (desabilitado quando há erro).
  final String? helperText;

  /// Callback de mudança de valor (cada keystroke).
  final ValueChanged<String>? onChanged;

  /// Callback de envio (pressionar Enter ou ação similar).
  final VoidCallback? onSubmitted;

  /// Controlador de texto (opcional; widget cria o seu se não fornecido).
  final TextEditingController? controller;

  /// Número de linhas (1 para single-line, null/maior para multi-line).
  final int? maxLines;

  /// Número máximo de linhas (quebra automática após isso).
  final int? minLines;

  /// Máximo de caracteres permitidos.
  final int? maxLength;

  /// Se verdadeiro, text é obscurecido (ex.: senha).
  final bool obscureText;

  /// Tipo de teclado (text, email, number, etc).
  final TextInputType keyboardType;

  /// Ícone auxiliar no sufixo do field.
  final AppInputSuffixIcon suffixIcon;

  /// Callback ao pressionar o ícone de sufixo.
  final VoidCallback? onSuffixIconPressed;

  /// Se verdadeiro, input é desabilitado.
  final bool enabled;

  /// TextInputAction (done, next, send, etc).
  final TextInputAction? textInputAction;

  /// Se verdadeiro, mostra contador de caracteres (quando maxLength > 0).
  final bool showCharacterCount;

  /// Autofocus no widget.
  final bool autofocus;

  /// TextStyle customizado para o input.
  final TextStyle? textStyle;

  /// TextStyle customizado para label.
  final TextStyle? labelStyle;

  const AppInput({
    super.key,
    required this.label,
    this.placeholder,
    this.error,
    this.helperText,
    this.onChanged,
    this.onSubmitted,
    this.controller,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.suffixIcon = AppInputSuffixIcon.none,
    this.onSuffixIconPressed,
    this.enabled = true,
    this.textInputAction,
    this.showCharacterCount = false,
    this.autofocus = false,
    this.textStyle,
    this.labelStyle,
  })  : assert(maxLines == null || maxLines > 0),
        assert(minLines == null || minLines > 0),
        assert(!(maxLines != null && minLines != null && minLines > maxLines));

  @override
  State<AppInput> createState() => _AppInputState();
}

class _AppInputState extends State<AppInput> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _isFocused = false;
  late bool _obscureText;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
    _obscureText = widget.obscureText;
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    setState(() {
      _isFocused = _focusNode.hasFocus;
    });
  }

  void _toggleObscureText() {
    setState(() {
      _obscureText = !_obscureText;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = scheme.brightness == Brightness.light;
    final isError = widget.error != null;
    final isFilled = _controller.text.isNotEmpty;

    // Cores baseadas em estado
    late final Color borderColor;
    late final Color labelColor;
    late final Color focusedBorderColor;
    late final Color errorBorderColor;
    late final Color hintColor;
    late final Color cursorColor;
    late final Color focusedFillColor;

    if (isLight) {
      borderColor = scheme.outline; // #E4DFD5
      labelColor = scheme.onSurfaceVariant; // #6B6A62 (cinza médio)
      focusedBorderColor = scheme.primary; // #3F7268 (verde floresta)
      errorBorderColor = scheme.error; // #A6503A (marrom avermelhado)
      hintColor = scheme.onSurfaceVariant.withValues(alpha: 0.5); // Cinza com opacidade
      cursorColor = scheme.primary;
      focusedFillColor = scheme.primary.withValues(alpha: 0.04); // Tint sutil
    } else {
      borderColor = scheme.outline; // #423F37
      labelColor = scheme.onSurfaceVariant; // #B2AEA3 (cinza médio claro)
      focusedBorderColor = scheme.primary; // #8FBFAE (verde claro)
      errorBorderColor = scheme.error; // #D98872 (laranja-avermelhado)
      hintColor = scheme.onSurfaceVariant.withValues(alpha: 0.5);
      cursorColor = scheme.primary;
      focusedFillColor = scheme.primary.withValues(alpha: 0.06);
    }

    // Determinar cores finais baseado em estado
    final effectiveBorderColor = isError
        ? errorBorderColor
        : (_isFocused ? focusedBorderColor : borderColor);

    final effectiveLabelColor = isError ? errorBorderColor : labelColor;

    final effectiveFillColor = (_isFocused && !isError)
        ? focusedFillColor
        : Colors.transparent;

    // Construir o input
    final input = TextFormField(
      controller: _controller,
      focusNode: _focusNode,
      obscureText: _obscureText && widget.obscureText,
      enabled: widget.enabled && !isError,
      autofocus: widget.autofocus,
      maxLines: _obscureText && widget.obscureText ? 1 : widget.maxLines,
      minLines: widget.minLines,
      maxLength: widget.maxLength,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      cursorColor: cursorColor,
      onChanged: widget.onChanged,
      onFieldSubmitted: (_) => widget.onSubmitted?.call(),
      style: widget.textStyle ??
          Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: scheme.onSurface,
                fontFamily: 'Atkinson Hyperlegible',
              ),
      decoration: InputDecoration(
        // Label sempre visível (não floating, sempre acima)
        label: Text(
          widget.label,
          style: widget.labelStyle ??
              Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: effectiveLabelColor,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Atkinson Hyperlegible',
                  ),
        ),
        floatingLabelBehavior: FloatingLabelBehavior.always,

        // Placeholder cinza/opaco
        hintText: widget.placeholder,
        hintStyle: TextStyle(
          color: hintColor,
          fontFamily: 'Atkinson Hyperlegible',
        ),

        // Padding generoso (12 dp vertical, 16 dp horizontal) para altura 48 dp
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),

        // Border
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(color: borderColor, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(color: borderColor, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(
            color: effectiveBorderColor,
            width: 2.0, // Mais grossa ao focar
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(
            color: errorBorderColor,
            width: 2.0,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(
            color: errorBorderColor,
            width: 2.0,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(
            color: borderColor.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),

        // Fundo
        fillColor: effectiveFillColor,
        filled: _isFocused || isFilled,

        // Ícone sufixo
        suffixIcon: _buildSuffixIcon(
          scheme,
          errorBorderColor,
        ),
        suffixIconConstraints:
            const BoxConstraints(minWidth: 48.0, minHeight: 48.0),

        // Error message clara abaixo
        errorText: isError ? widget.error : null,
        errorStyle: TextStyle(
          color: errorBorderColor,
          fontFamily: 'Atkinson Hyperlegible',
          fontSize: 12.0,
        ),

        // Helper text (desabilitado quando há erro)
        helperText: isError ? null : widget.helperText,
        helperStyle: TextStyle(
          color: labelColor.withValues(alpha: 0.7),
          fontFamily: 'Atkinson Hyperlegible',
          fontSize: 12.0,
        ),

        // Contador de caracteres
        counterText: widget.showCharacterCount ? null : '',
        counterStyle: TextStyle(
          color: labelColor.withValues(alpha: 0.7),
          fontFamily: 'Atkinson Hyperlegible',
          fontSize: 12.0,
        ),
      ),
    );

    // Opacidade reduzida para disabled
    return Opacity(
      opacity: widget.enabled ? 1.0 : 0.6,
      child: input,
    );
  }

  /// Constrói o widget do ícone sufixo (clear, show-password, info, ou nenhum).
  Widget? _buildSuffixIcon(ColorScheme scheme, Color errorColor) {
    final isError = widget.error != null;
    final iconColor = isError
        ? errorColor
        : (_isFocused ? scheme.primary : scheme.onSurfaceVariant);

    switch (widget.suffixIcon) {
      case AppInputSuffixIcon.clear:
        return _controller.text.isEmpty
            ? null
            : IconButton(
                icon: Icon(Icons.clear, color: iconColor, size: 20.0),
                onPressed: widget.onSuffixIconPressed ?? _clearInput,
                tooltip: 'Limpar',
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                constraints: const BoxConstraints(
                  minWidth: 40.0,
                  minHeight: 40.0,
                ),
              );

      case AppInputSuffixIcon.showPassword:
        return IconButton(
          icon: Icon(
            _obscureText ? Icons.visibility_off : Icons.visibility,
            color: iconColor,
            size: 20.0,
          ),
          onPressed: widget.onSuffixIconPressed ?? _toggleObscureText,
          tooltip: _obscureText ? 'Mostrar' : 'Ocultar',
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          constraints: const BoxConstraints(
            minWidth: 40.0,
            minHeight: 40.0,
          ),
        );

      case AppInputSuffixIcon.info:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: Icon(
            Icons.info_outline,
            color: iconColor,
            size: 20.0,
          ),
        );

      case AppInputSuffixIcon.none:
        return null;
    }
  }

  void _clearInput() {
    _controller.clear();
    widget.onChanged?.call('');
  }
}
