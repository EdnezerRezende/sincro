import 'package:flutter/material.dart';
import 'row_icon.dart';

/// Linha padrão de um `SectionCard` na direção A: ícone tonal (`RowIcon`) à esquerda, título
/// 16 bold, subtítulo 14 em `onSurfaceVariant` e, à direita, o `trailing` informado ou um
/// chevron quando a linha é tocável. Altura mínima de 56 dp (48 dp em `dense`).
///
/// Variações de estilo da tela inicial passam por aqui sem mudar a estrutura:
/// - `dense` (Funcional Direto): ícone simples de 20 dp em vez do tile, linha de 48 dp.
/// - `gradient` (Moderno Suave): o tile do ícone ganha o degradê sutil de `RowIcon`.
/// - `destructive`: título e ícone na cor `error` (ações como "Sair" e "Apagar").
///
/// Cores só do `ColorScheme`, para funcionar nos temas claro e escuro.
class SectionRow extends StatelessWidget {
  const SectionRow({
    super.key,
    required this.title,
    this.icon,
    this.leading,
    this.subtitle,
    this.subtitleWidget,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.destructive = false,
    this.dense = false,
    this.gradient = false,
    this.accent,
  }) : assert(subtitle == null || subtitleWidget == null, 'Use subtitle ou subtitleWidget, não ambos');

  final String title;

  /// Ícone do tile à esquerda. Ignorado quando `leading` é informado.
  final IconData? icon;

  /// Substitui o tile de ícone por um widget qualquer.
  final Widget? leading;

  final String? subtitle;
  final Widget? subtitleWidget;

  /// Widget à direita. Quando nulo e a linha é tocável, mostra um chevron.
  final Widget? trailing;

  final VoidCallback? onTap;

  /// `false` desabilita o toque sem tirar o chevron — usado enquanto a tela está ocupada.
  final bool enabled;

  final bool destructive;
  final bool dense;
  final bool gradient;

  /// Cor de destaque do ícone (padrão `primary`; `error` quando `destructive`).
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = destructive ? scheme.error : (accent ?? scheme.primary);

    final Widget? leadingWidget = leading ??
        (icon == null
            ? null
            : dense
                ? Icon(icon, size: 20, color: destructive ? scheme.error : scheme.onSurfaceVariant)
                : RowIcon(icon!, accent: color, gradient: gradient));

    final Widget? trailingWidget = trailing ??
        (onTap != null ? Icon(Icons.chevron_right, color: scheme.onSurfaceVariant) : null);

    return ListTile(
      enabled: enabled,
      onTap: enabled ? onTap : null,
      minTileHeight: dense ? 48 : 56,
      minVerticalPadding: dense ? 4 : 8,
      leading: leadingWidget,
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: destructive ? scheme.error : scheme.onSurface,
        ),
      ),
      subtitle: subtitleWidget ??
          (subtitle == null
              ? null
              : Text(subtitle!, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))),
      trailing: trailingWidget,
    );
  }
}
