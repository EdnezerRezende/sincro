import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_button.dart';

/// Ação de diálogo: botão com label, callback e tipo de ação.
/// O tipo determina estilo visual (primário, secundário, destrutivo).
class DialogAction {
  /// Texto exibido no botão.
  final String label;

  /// Callback ao pressionar (null = botão desabilitado).
  final VoidCallback? onPressed;

  /// Tipo de ação: 'primary' (cor destaque), 'secondary' (outline), 'destructive' (vermelho).
  /// Padrão é 'secondary'.
  final String type;

  /// Se true, fecha o diálogo automaticamente após onPressed.
  /// Padrão é true.
  final bool closeOnPressed;

  const DialogAction({
    required this.label,
    required this.onPressed,
    this.type = 'secondary',
    this.closeOnPressed = true,
  });
}

/// Diálogo reutilizável com título, conteúdo, ações e animação suave.
/// Segue Material Design 3 com dark mode integrado.
///
/// Uso básico:
/// ```dart
/// showAppDialog(
///   context,
///   title: 'Confirmar ação',
///   content: 'Tem certeza que deseja deletar?',
///   actions: [
///     DialogAction(
///       label: 'Cancelar',
///       onPressed: () {},
///       type: 'secondary',
///     ),
///     DialogAction(
///       label: 'Deletar',
///       onPressed: () { /* ação */ },
///       type: 'destructive',
///     ),
///   ],
/// )
/// ```
///
/// Com conteúdo customizado:
/// ```dart
/// showAppDialog(
///   context,
///   title: 'Configurar',
///   contentWidget: MyConfigWidget(),
///   actions: [],
/// )
/// ```
class AppDialog extends StatefulWidget {
  /// Título do diálogo (grande, bold).
  final String? title;

  /// Conteúdo textual (string simples).
  final String? content;

  /// Conteúdo customizado (widget). Sobrescreve `content` se fornecido.
  final Widget? contentWidget;

  /// Ações (botões) — até 2 recomendado.
  final List<DialogAction> actions;

  /// Callback ao clicar fora (scrim). Se null, não fecha automaticamente.
  /// Padrão é fechar.
  final VoidCallback? onScrimTap;

  /// Se true, fechar com ESC. Padrão é true.
  final bool closeOnEscape;

  /// Se true, fechar ao clicar fora (scrim). Padrão é true.
  final bool closeOnScrimTap;

  /// Cor do scrim (fundo semi-transparente). Padrão é 70% preto.
  final Color? scrimColor;

  /// Duração da animação de entrada (fade/scale). Padrão é 200ms.
  final Duration animationDuration;

  /// Padding interno do diálogo. Padrão é 24dp.
  final EdgeInsets contentPadding;

  /// Altura máxima do conteúdo (para scrolling). Se null, sem limite.
  final double? maxContentHeight;

  const AppDialog({
    super.key,
    this.title,
    this.content,
    this.contentWidget,
    this.actions = const [],
    this.onScrimTap,
    this.closeOnEscape = true,
    this.closeOnScrimTap = true,
    this.scrimColor,
    this.animationDuration = const Duration(milliseconds: 200),
    this.contentPadding = const EdgeInsets.all(24.0),
    this.maxContentHeight,
  });

  @override
  State<AppDialog> createState() => _AppDialogState();
}

class _AppDialogState extends State<AppDialog> with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // Animação de fade (0 -> 1)
    _fadeController = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );
    _fadeAnimation =
        Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
        );

    // Animação de scale (0.8 -> 1.0)
    _scaleController = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOutCubic),
    );

    // Inicia as animações
    _fadeController.forward();
    _scaleController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  /// Fecha o diálogo com animação reversa (opcional).
  Future<void> _closeDialog() async {
    if (mounted) {
      // Fade out
      await Future.wait([
        _fadeController.reverse(),
        _scaleController.reverse(),
      ]);
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.of(context).size.width < 600;

    // Cor do scrim (70% preto por padrão, adaptado a light/dark)
    final defaultScrimColor = scheme.brightness == Brightness.light
        ? Colors.black.withValues(alpha: 0.7)
        : Colors.black.withValues(alpha: 0.8);

    final scrimColor = widget.scrimColor ?? defaultScrimColor;

    // Diálogo com keyboard handler para ESC
    return Focus(
      onKeyEvent: widget.closeOnEscape
          ? (node, event) {
              // ESC para fechar
              if (event.logicalKey == LogicalKeyboardKey.escape) {
                _closeDialog();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            }
          : null,
      child: GestureDetector(
        onTap: widget.closeOnScrimTap
            ? () {
                widget.onScrimTap?.call();
                _closeDialog();
              }
            : null,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: scrimColor,
            child: Center(
              child: GestureDetector(
                onTap: () {
                  // Evita fechar ao clicar dentro do diálogo
                },
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: _buildDialogContent(context, scheme, isMobile),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Constrói o conteúdo principal do diálogo (card branco/escuro).
  Widget _buildDialogContent(BuildContext context, ColorScheme scheme, bool isMobile) {
    return Material(
      type: MaterialType.card,
      color: scheme.surface,
      elevation: 8.0,
      shadowColor: scheme.brightness == Brightness.light
          ? Colors.black.withValues(alpha: 0.15)
          : Colors.black.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: isMobile ? double.infinity : 400,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        margin: isMobile ? const EdgeInsets.symmetric(horizontal: 16.0) : null,
        padding: widget.contentPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Título
            if (widget.title != null) ...[
              Text(
                widget.title!,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12.0),
            ],

            // Conteúdo (text ou widget customizado)
            if (widget.contentWidget != null) ...[
              Flexible(
                child: SingleChildScrollView(
                  child: widget.contentWidget!,
                ),
              ),
            ] else if (widget.content != null) ...[
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    widget.content!,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ),
            ],

            // Espaçador entre conteúdo e ações
            if (widget.actions.isNotEmpty) ...[
              const SizedBox(height: 24.0),
            ],

            // Ações (botões)
            _buildActions(context, scheme),
          ],
        ),
      ),
    );
  }

  /// Constrói a linha de botões (ações).
  /// Até 2 botões em linha; mais que 2, em coluna ou scroll.
  Widget _buildActions(BuildContext context, ColorScheme scheme) {
    if (widget.actions.isEmpty) {
      return const SizedBox.shrink();
    }

    final isMobile = MediaQuery.of(context).size.width < 600;

    // Se 2 ou menos botões, em Row; senão em Column.
    final isHorizontal = widget.actions.length <= 2 && !isMobile;

    final buttons = <Widget>[
      for (int i = 0; i < widget.actions.length; i++) ...[
        _buildActionButton(context, widget.actions[i], i),
        if (isHorizontal && i < widget.actions.length - 1)
          const SizedBox(width: 12.0),
      ],
    ];

    if (isHorizontal) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: buttons,
      );
    } else {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: buttons,
      );
    }
  }

  /// Constrói um único botão de ação.
  Widget _buildActionButton(BuildContext context, DialogAction action, int index) {
    final scheme = Theme.of(context).colorScheme;

    // Determina variante e cor conforme tipo de ação
    late final AppButtonVariant variant;
    late final Color? foregroundColor;

    switch (action.type) {
      case 'primary':
        variant = AppButtonVariant.primary;
        foregroundColor = null; // Usa padrão (scheme.onPrimary)
        break;

      case 'destructive':
        // Botão "destrutivo" com cor de erro (vermelho dessaturado)
        variant = AppButtonVariant.primary;
        foregroundColor = scheme.error;
        break;

      case 'secondary':
      default:
        variant = AppButtonVariant.outline;
        foregroundColor = null;
        break;
    }

    return Expanded(
      child: _ActionButton(
        label: action.label,
        onPressed: action.onPressed == null
            ? null
            : () async {
          // Executa callback
          action.onPressed?.call();
          // Fecha diálogo (se configurado)
          if (action.closeOnPressed && mounted) {
            await _closeDialog();
          }
        },
        variant: variant,
        destructiveColor: action.type == 'destructive' ? foregroundColor : null,
      ),
    );
  }
}

/// Botão customizado para ações de diálogo.
/// Permite sobrescrever cor (útil para "destructive").
class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final Color? destructiveColor;

  const _ActionButton({
    required this.label,
    required this.onPressed,
    required this.variant,
    this.destructiveColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Se destrutivo, usa ButtonStyle customizado
    if (destructiveColor != null) {
      return ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: destructiveColor,
          foregroundColor: scheme.onError,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          disabledBackgroundColor:
              destructiveColor?.withValues(alpha: 0.4) ?? Colors.grey.withValues(alpha: 0.4),
          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.4),
        ),
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      );
    }

    // Usa AppButton padrão para outras variantes
    return AppButton(
      label: label,
      onPressed: onPressed,
      variant: variant,
      size: AppButtonSize.medium,
    );
  }
}

/// Função helper para exibir AppDialog facilmente.
/// Retorna `Future<void>` que completa quando o diálogo é fechado.
Future<void> showAppDialog(
  BuildContext context, {
  String? title,
  String? content,
  Widget? contentWidget,
  List<DialogAction>? actions,
  VoidCallback? onScrimTap,
  bool closeOnEscape = true,
  bool closeOnScrimTap = true,
  Color? scrimColor,
  Duration animationDuration = const Duration(milliseconds: 200),
  EdgeInsets contentPadding = const EdgeInsets.all(24.0),
  double? maxContentHeight,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false, // Controlado via closeOnScrimTap
    builder: (BuildContext context) => AppDialog(
      title: title,
      content: content,
      contentWidget: contentWidget,
      actions: actions ?? [],
      onScrimTap: onScrimTap,
      closeOnEscape: closeOnEscape,
      closeOnScrimTap: closeOnScrimTap,
      scrimColor: scrimColor,
      animationDuration: animationDuration,
      contentPadding: contentPadding,
      maxContentHeight: maxContentHeight,
    ),
  );
}
