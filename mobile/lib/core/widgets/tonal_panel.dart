import 'package:flutter/material.dart';

/// Painel tonal da direção A: fundo `primary` a 6 %, borda `primary` a 25 %, raio 16. É o chrome
/// do cartão de destaque de Finanças na Home e do "Estado atual" do Biofeedback.
///
/// `gradient: true` (Moderno Suave) troca o fundo chapado por um degradê sutil `primary` →
/// `secondary`. `borderColor` permite a borda mais forte do Funcional Direto. Toda cor vem do
/// `ColorScheme`, então o painel funciona nos temas claro e escuro.
class TonalPanel extends StatelessWidget {
  const TonalPanel({
    super.key,
    required this.child,
    this.onTap,
    this.gradient = false,
    this.borderColor,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool gradient;
  final Color? borderColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final decoration = BoxDecoration(
      color: gradient ? null : scheme.primary.withAlpha(15),
      gradient: gradient
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [scheme.primary.withAlpha(31), scheme.secondary.withAlpha(10)],
            )
          : null,
      border: Border.all(color: borderColor ?? scheme.primary.withAlpha(64)),
      borderRadius: BorderRadius.circular(16),
    );

    final content = Padding(padding: padding, child: child);
    if (onTap == null) {
      return Container(decoration: decoration, child: content);
    }
    return Container(
      decoration: decoration,
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(onTap: onTap, child: content),
      ),
    );
  }
}
