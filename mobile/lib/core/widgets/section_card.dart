import 'package:flutter/material.dart';

/// Cartão agrupado da direção A: título opcional (16 bold) + `Card` do tema com linhas
/// separadas por divisores internos. As linhas costumam ser `SectionRow`s de 56 dp.
///
/// `borderColor` permite a borda mais forte do estilo Funcional Direto (≥ 2,5:1 contra o
/// fundo); o padrão é `colorScheme.outline`, como na prancha. Cores só do `ColorScheme`, para
/// funcionar nos temas claro e escuro.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.children,
    this.title,
    this.borderColor,
  });

  final List<Widget> children;
  final String? title;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(Divider(height: 1, indent: 16, endIndent: 16, color: scheme.outline));
      rows.add(children[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Text(title!, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
        ],
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: borderColor ?? scheme.outline),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: rows),
        ),
      ],
    );
  }
}
