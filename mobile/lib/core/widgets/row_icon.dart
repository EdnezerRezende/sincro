import 'package:flutter/material.dart';

/// Ícone em "tile" tonal da direção A: quadrado de 40 dp, raio 12, fundo `primary` a 10 % e
/// ícone de 20 dp na cor de destaque. É o marcador visual das linhas de `SectionCard`.
///
/// Toda cor vem do `ColorScheme`, então o tile funciona igual nos temas claro e escuro.
/// `gradient: true` é o traço do estilo Moderno Suave: em vez do fundo chapado, um degradê sutil
/// entre o destaque e a `secondary`.
class RowIcon extends StatelessWidget {
  const RowIcon(
    this.icon, {
    super.key,
    this.accent,
    this.gradient = false,
    this.size = 40,
  });

  final IconData icon;

  /// Cor de destaque do ícone e do fundo tonal. Padrão: `colorScheme.primary`.
  final Color? accent;

  /// Estilo Moderno Suave: fundo em degradê sutil em vez de tonal chapado.
  final bool gradient;

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = accent ?? scheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: gradient ? null : color.withAlpha(26),
        gradient: gradient
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color.withAlpha(46), scheme.secondary.withAlpha(20)],
              )
            : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: size / 2),
    );
  }
}
