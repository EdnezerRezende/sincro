import 'package:flutter/material.dart';

/// Border idle contra scaffold `#FAF8F5` (light) / `#1A1F23` (dark).
/// Light: #9C9690 ≈ 2.76:1 contra #FAF8F5. Dark: #66605A ≈ 2.68:1 contra #1A1F23.
const Color _kBorderLight = Color(0xFF9C9690);
const Color _kBorderDark = Color(0xFF66605A);

/// Disabled fill contra scaffold `#FAF8F5` (light) / `#1A1F23` (dark).
/// Light: #928C86 ≈ 3.14:1 contra #FAF8F5. Dark: #6E6862 ≈ 3.02:1 contra #1A1F23.
const Color _kDisabledBgLight = Color(0xFF928C86);
const Color _kDisabledBgDark = Color(0xFF6E6862);

/// Disabled border contra o próprio fill disabled (≥3:1) para dar forma ao campo.
/// Light: #433D39 ≈ 3.22:1 contra #928C86 (L=0.266). Dark: #C0C0C0 ≈ 3.02:1 contra #6E6862 (L=0.139).
const Color _kDisabledBorderLight = Color(0xFF433D39);
const Color _kDisabledBorderDark = Color(0xFFC0C0C0);

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

  /// Texto de erro exibido abaixo do field.
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
    _controller.addListener(_handleControllerChange);
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
    _obscureText = widget.obscureText;
  }

  @override
  void didUpdateWidget(AppInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _controller.removeListener(_handleControllerChange);
      if (oldWidget.controller == null) _controller.dispose();
      _controller = widget.controller ?? TextEditingController();
      _controller.addListener(_handleControllerChange);
    }
    if (oldWidget.obscureText != widget.obscureText) {
      _obscureText = widget.obscureText;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChange);
    if (widget.controller == null) {
      _controller.dispose();
    }
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleControllerChange() {
    setState(() {});
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
      borderColor = _kBorderLight;
      labelColor = scheme.onSurfaceVariant;
      focusedBorderColor = scheme.primary;
      errorBorderColor = scheme.error;
      hintColor = scheme.onSurfaceVariant; // Sólido — alpha 0.5 dava apenas 2.07:1
      cursorColor = scheme.primary;
      focusedFillColor = scheme.primary.withValues(alpha: 0.04);
    } else {
      borderColor = _kBorderDark;
      labelColor = scheme.onSurfaceVariant;
      focusedBorderColor = scheme.primary;
      errorBorderColor = scheme.error;
      hintColor = scheme.onSurfaceVariant; // Sólido — alpha 0.5 dava apenas 2.07:1
      cursorColor = scheme.primary;
      focusedFillColor = scheme.primary.withValues(alpha: 0.06);
    }

    // Determinar cores finais baseado em estado
    final effectiveBorderColor = isError
        ? errorBorderColor
        : (_isFocused ? focusedBorderColor : borderColor);

    // Quando disabled, o label pode cair parcialmente sobre o fill disabled —
    // usar cor com ≥4.5:1 tanto sobre o scaffold quanto sobre _kDisabledBg.
    // Light: #1A1A1A → 6.0:1/fill, 16.7:1/scaffold. Dark: #EEEEEE → 4.8:1/fill, 12.2:1/scaffold.
    // !enabled vence sobre isError: o erro é sinalizado pela borda 2dp e errorText.
    final disabledLabelColor =
        isLight ? const Color(0xFF1A1A1A) : const Color(0xFFEEEEEE);
    final effectiveLabelColor = !widget.enabled
        ? disabledLabelColor
        : (isError ? errorBorderColor : labelColor);

    final disabledFillColor =
        isLight ? _kDisabledBgLight : _kDisabledBgDark;

    final effectiveFillColor = !widget.enabled
        ? disabledFillColor
        : (_isFocused && !isError)
            ? focusedFillColor
            : Colors.transparent;

    // Construir o input
    final input = TextFormField(
      controller: _controller,
      focusNode: _focusNode,
      obscureText: _obscureText && widget.obscureText,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      maxLines: _obscureText && widget.obscureText ? 1 : widget.maxLines,
      minLines: widget.minLines,
      maxLength: widget.maxLength,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      cursorColor: cursorColor,
      onChanged: widget.onChanged,
      onFieldSubmitted: (_) => widget.onSubmitted?.call(),
      style: (Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: scheme.onSurface,
                fontFamily: 'Atkinson Hyperlegible',
              ) ??
              TextStyle(color: scheme.onSurface))
          .merge(widget.textStyle),
      decoration: InputDecoration(
        // Label sempre visível (não floating, sempre acima)
        label: Text(
          widget.label,
          style: (Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: effectiveLabelColor,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Atkinson Hyperlegible',
                  ) ??
                  TextStyle(color: effectiveLabelColor))
              .merge(widget.labelStyle),
        ),
        floatingLabelBehavior: FloatingLabelBehavior.always,

        // Placeholder — oculto no estado disabled (campo não aceita entrada;
        // placeholder sobre o fill disabled daria contraste insuficiente).
        hintText: widget.enabled ? widget.placeholder : null,
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
          // Quando disabled, a borda de erro usaria vermelho sobre fill morto (1.69:1).
          // Usar a borda disabled: o erro é sinalizado pelo errorText no scaffold.
          borderSide: BorderSide(
            color: !widget.enabled
                ? (isLight ? _kDisabledBorderLight : _kDisabledBorderDark)
                : errorBorderColor,
            width: !widget.enabled ? 1.0 : 2.0,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(
            color: !widget.enabled
                ? (isLight ? _kDisabledBorderLight : _kDisabledBorderDark)
                : errorBorderColor,
            width: !widget.enabled ? 1.0 : 2.0,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(
            // Borda ≥3:1 contra o fill disabled para dar forma ao campo.
            color: isLight ? _kDisabledBorderLight : _kDisabledBorderDark,
            width: 1.0,
          ),
        ),

        // Fundo
        fillColor: effectiveFillColor,
        filled: !widget.enabled || _isFocused || isFilled,

        // Ícone sufixo
        suffixIcon: _buildSuffixIcon(
          scheme,
          errorBorderColor,
        ),
        suffixIconConstraints:
            const BoxConstraints(minWidth: 48.0, minHeight: 48.0),

        // Error message clara abaixo — permite quebra de linha em alta escala
        errorText: isError ? widget.error : null,
        errorMaxLines: 3,
        errorStyle: TextStyle(
          color: errorBorderColor,
          fontFamily: 'Atkinson Hyperlegible',
          fontSize: 12.0,
        ),

        // Helper text (desabilitado quando há erro) — permite quebra de linha
        helperText: isError ? null : widget.helperText,
        helperMaxLines: 3,
        helperStyle: TextStyle(
          color: labelColor, // Sólido — alpha 0.7 dava apenas 2.94:1
          fontFamily: 'Atkinson Hyperlegible',
          fontSize: 12.0,
        ),

        // Contador de caracteres
        counterText: widget.showCharacterCount ? null : '',
        counterStyle: TextStyle(
          color: labelColor, // Sólido — alpha 0.7 dava apenas 2.94:1
          fontFamily: 'Atkinson Hyperlegible',
          fontSize: 12.0,
        ),
      ),
    );

    return input;
  }

  /// Constrói o widget do ícone sufixo (clear, show-password, info, ou nenhum).
  Widget? _buildSuffixIcon(ColorScheme scheme, Color errorColor) {
    // Suprimir ícones interativos quando disabled — sua cor ficaria ilegível
    // sobre o fill disabled e o campo não aceita interação de qualquer forma.
    if (!widget.enabled) return null;

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
