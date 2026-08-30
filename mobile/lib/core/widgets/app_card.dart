import 'package:flutter/material.dart';

/// Variantes do card Sincro: elevado (sombra sutil) ou plano (border).
enum AppCardVariant {
  /// Card com sombra sutil — feedback de elevação clara.
  elevated,

  /// Card com border — estilo outline, mais minimalista.
  flat,
}

/// Card reutilizável Sincro com 2 variantes, estados (normal/selected), títulos/subtítulos,
/// ícone opcional, ações, espaçamento consistente (16 dp), dark mode nativo.
/// Elegante, sem truncamento, hierarquia clara.
///
/// Uso básico:
/// ```dart
/// AppCard(
///   title: 'Título',
///   subtitle: 'Descrição',
///   onTap: () { /* ... */ },
///   variant: AppCardVariant.elevated,
/// )
/// ```
///
/// Com ícone e ações:
/// ```dart
/// AppCard(
///   title: 'Email de cobrança',
///   subtitle: 'Vence em 5 dias',
///   icon: Icons.mail,
///   actions: [
///     IconButton(icon: Icon(Icons.edit), onPressed: () {}),
///     IconButton(icon: Icon(Icons.delete), onPressed: () {}),
///   ],
///   selected: isSelected,
///   variant: AppCardVariant.elevated,
/// )
/// ```
///
/// Em lista com espaçamento:
/// ```dart
/// ListView.builder(
///   itemCount: items.length,
///   itemBuilder: (context, i) => Padding(
///     padding: EdgeInsets.only(bottom: 16.0),
///     child: AppCard(title: items[i].name),
///   ),
/// )
/// ```
class AppCard extends StatefulWidget {
  /// Título principal (obrigatório).
  final String title;

  /// Subtítulo/descrição (opcional).
  final String? subtitle;

  /// Ícone à esquerda do título (opcional).
  final IconData? icon;

  /// Cor customizada para o ícone (padrão: cor do tema).
  final Color? iconColor;

  /// Conteúdo custom sob título/subtitle (opcional — substitui subtitle se fornecido).
  final Widget? child;

  /// Lista de ações (botões, ícones) no canto superior direito.
  final List<Widget>? actions;

  /// Callback quando o card é tocado (torna card tátil).
  final VoidCallback? onTap;

  /// Se true, card aparece em estado "selected" com feedback visual.
  final bool selected;

  /// Variante visual: elevated (sombra) ou flat (border).
  final AppCardVariant variant;

  /// Padding interno (padrão: 16 dp).
  final EdgeInsets padding;

  /// Cor de fundo customizada (padrão: surface do tema).
  final Color? backgroundColor;

  /// Habilitado/desabilitado (reduz opacidade se false).
  final bool enabled;

  const AppCard({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.child,
    this.actions,
    this.onTap,
    this.selected = false,
    this.variant = AppCardVariant.elevated,
    this.padding = const EdgeInsets.all(16.0),
    this.backgroundColor,
    this.enabled = true,
  });

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Cores e estilos baseados em estado e variante
    final bgColor = widget.backgroundColor ?? scheme.surface;
    final effectiveOpacity = widget.enabled ? 1.0 : 0.6;

    // Determinar cor de border/sombra
    late final Color accentColor;
    late final double elevation;
    late final BorderSide? borderSide;

    if (widget.selected) {
      // Estado selecionado: border/sombra mais proeminente, cor primary
      accentColor = scheme.primary;
      elevation = widget.variant == AppCardVariant.elevated ? 8.0 : 0.0;
      borderSide = widget.variant == AppCardVariant.flat
          ? BorderSide(color: accentColor, width: 2.0)
          : null;
    } else {
      // Estado normal: border/sombra sutil
      accentColor = scheme.outline;
      elevation = widget.variant == AppCardVariant.elevated ? 1.0 : 0.0;
      borderSide = widget.variant == AppCardVariant.flat
          ? BorderSide(color: accentColor, width: 1.0)
          : null;
    }

    // Construir conteúdo interno
    final cardContent = Padding(
      padding: widget.padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: ícone + título (esquerda) + ações (direita)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ícone (se fornecido)
              if (widget.icon != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12.0, top: 2.0),
                  child: Icon(
                    widget.icon,
                    size: 24.0,
                    color: widget.iconColor ?? scheme.primary,
                  ),
                ),

              // Título (expansível)
              Expanded(
                child: Text(
                  widget.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Ações (canto superior direito)
              if (widget.actions != null && widget.actions!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 12.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: widget.actions!,
                  ),
                ),
            ],
          ),

          // Conteúdo: subtitle ou child custom
          if (widget.subtitle != null || widget.child != null)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: widget.child ??
                  Text(
                    widget.subtitle!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
            ),
        ],
      ),
    );

    // Construir card com border/elevation
    final card = Material(
      elevation: elevation,
      shadowColor: scheme.outline.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(16.0)),
        side: borderSide ?? BorderSide.none,
      ),
      color: bgColor,
      child: cardContent,
    );

    // Wrapper tátil (se onTap fornecido)
    final tappable = widget.onTap != null
        ? Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.enabled ? widget.onTap : null,
              borderRadius: const BorderRadius.all(Radius.circular(16.0)),
              child: card,
            ),
          )
        : card;

    // Aplicar opacidade se desabilitado
    return Opacity(
      opacity: effectiveOpacity,
      child: tappable,
    );
  }
}

/// Wrapper para exibir múltiplos cards com espaçamento consistente (gap >= 16 dp).
/// Quebra automaticamente em várias linhas em telas estreitas.
class AppCardGroup extends StatelessWidget {
  /// Lista de cards a exibir.
  final List<AppCard> cards;

  /// Espaçamento horizontal entre cards.
  final double spacing;

  /// Espaçamento vertical entre linhas de cards.
  final double runSpacing;

  /// Alinhamento horizontal.
  final WrapAlignment alignment;

  /// Se true, exibe cards em coluna (um por linha) — útil para mobile.
  final bool isColumn;

  const AppCardGroup({
    super.key,
    required this.cards,
    this.spacing = 16.0,
    this.runSpacing = 16.0,
    this.alignment = WrapAlignment.start,
    this.isColumn = false,
  })  : assert(spacing >= 16.0),
        assert(runSpacing >= 16.0);

  @override
  Widget build(BuildContext context) {
    if (isColumn) {
      // Coluna com espaçamento
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < cards.length; i++) ...[
            cards[i],
            if (i < cards.length - 1) SizedBox(height: runSpacing),
          ]
        ],
      );
    } else {
      // Wrap para layout responsivo
      return Wrap(
        spacing: spacing,
        runSpacing: runSpacing,
        alignment: alignment,
        children: cards,
      );
    }
  }
}
