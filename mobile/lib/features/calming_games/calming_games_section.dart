import 'package:flutter/material.dart';

import 'estrada_tranquila_screen.dart';
import 'voo_sereno_screen.dart';

/// Seção "Jogos para acalmar", exibida no topo da biblioteca de alívio
/// sensorial (`GroundingCardsLibraryScreen`): dois convites para os
/// minijogos de regulação sensorial "Voo Sereno" e "Estrada Tranquila".
///
/// Sem placar, sem tempo, sem erro — cada card leva a uma sessão nova
/// (semente por sessão, baseada no relógio) e nunca falha ou pontua.
class CalmingGamesSection extends StatelessWidget {
  const CalmingGamesSection({super.key});

  int _novaSemente() => DateTime.now().millisecondsSinceEpoch & 0x7fffffff;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Jogos para acalmar', style: theme.textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(
                'Sem placar, sem tempo, sem erro. Só movimento lento.',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _CalmingGameCard(
          icon: Icons.flight_takeoff_rounded,
          title: 'Voo Sereno',
          description: 'Deslize o avião de papel pelo céu, no ritmo da respiração.',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => VooSerenoScreen(seed: _novaSemente())),
            );
          },
        ),
        const SizedBox(height: 12),
        _CalmingGameCard(
          icon: Icons.directions_car_filled_rounded,
          title: 'Estrada Tranquila',
          description: 'Dirija devagar por uma estrada sem obstáculos, ao entardecer.',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EstradaTranquilaScreen(seed: _novaSemente())),
            );
          },
        ),
      ],
    );
  }
}

class _CalmingGameCard extends StatelessWidget {
  const _CalmingGameCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final borderRadius = BorderRadius.circular(16);

    return Semantics(
      button: true,
      label: '$title. $description',
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 88),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: scheme.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          description,
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '~3 min · sem placar',
                          style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
