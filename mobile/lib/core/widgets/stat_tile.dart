import 'package:flutter/material.dart';

/// Tile de estatística da direção A (prancha Biofeedback): rótulo 14 em `onSurfaceVariant` e
/// valor 34 bold em `primary`, com a unidade em 16 regular ao lado. Cartão branco com borda
/// `outline` e raio 16, como os demais cartões agrupados.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.semanticsLabel,
  });

  final String label;
  final String value;
  final String? unit;

  /// Leitura por voz do tile inteiro (ex.: "Frequência cardíaca em repouso hoje: 68 bpm").
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: semanticsLabel != null,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  text: value,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontSize: 34,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                  children: [
                    if (unit != null)
                      TextSpan(
                        text: ' $unit',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w400,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
