import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import 'email_detail_screen.dart';
import 'email_summary.dart';
import 'email_triage_providers.dart';

class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summariesAsync = ref.watch(emailSummariesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Caixa de Entrada')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(emailSummariesProvider),
        child: summariesAsync.when(
          data: (summaries) {
            if (summaries.isEmpty) {
              return const _EmptyState();
            }
            final precisamAtencao = summaries.where((s) => s.precisaAtencao).toList();
            final podemEsperar = summaries.where((s) => !s.precisaAtencao).toList();

            final items = <_InboxListItem>[
              if (precisamAtencao.isNotEmpty) ...[
                _InboxListItem.header('Precisam de atenção', precisamAtencao.length, isPending: true),
                ...precisamAtencao.map(_InboxListItem.email),
              ],
              if (podemEsperar.isNotEmpty) ...[
                _InboxListItem.header('Podem esperar', podemEsperar.length, isPending: false),
                ...podemEsperar.map(_InboxListItem.email),
              ],
            ];

            // Cap content width on large screens so text lines stay readable instead of
            // stretching edge-to-edge; harmless on phone widths where 720 never binds.
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return item.isHeader
                        ? _SectionHeader(
                            title: item.title!,
                            count: item.count,
                            isPending: item.isPending,
                          )
                        : _EmailTile(summary: item.summary!);
                  },
                ),
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => _ErrorState(
            onRetry: () => ref.invalidate(emailSummariesProvider),
          ),
        ),
      ),
    );
  }
}

/// A single row for the lazily-built list: either a section header or an email tile. Keeping the
/// section grouping as a flat, indexable list (instead of nested widget subtrees) is what lets
/// ListView.builder build tiles on demand instead of the whole inbox eagerly.
class _InboxListItem {
  const _InboxListItem.header(this.title, this.count, {required this.isPending})
      : summary = null,
        isHeader = true;

  const _InboxListItem.email(this.summary)
      : title = null,
        count = 0,
        isPending = false,
        isHeader = false;

  final String? title;
  final EmailSummary? summary;
  final bool isHeader;
  final int count;
  final bool isPending;
}

/// Empty inbox state: reassures the user there's nothing pending rather than showing a bare
/// string on a blank screen.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 48),
              Icon(
                Icons.mark_email_read_outlined,
                size: 48,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'Nenhum e-mail novo por aqui.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Load-failure state: surfaces a visible retry action instead of relying solely on the
/// pull-to-refresh gesture, which isn't discoverable.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 48),
              Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'Não foi possível carregar seus e-mails.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: onRetry,
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Section header: title plus a count badge. The "needs attention" section uses the caution
/// (amber) color for its badge, matching the same color used on the tiles themselves so the
/// association holds even after this header scrolls out of view.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    this.isPending = false,
  });

  final String title;
  final int count;
  final bool isPending;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final sincroColors = context.sincroColors;

    final badgeColor = isPending ? sincroColors.caution : colors.onSurfaceVariant;

    return Padding(
      // 16/24/16/12: on the 8dp grid (theme.dart _spacing4/_spacing6/_spacing3) — the
      // previous top inset of 20 was off-grid.
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            // horizontal 8 (was 10, off-grid) — theme.dart _spacing2.
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: badgeColor.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  count.toString(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: badgeColor,
                        fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A single inbox row.
///
/// Emails that need attention get the caution (amber) color on the tile itself — a left accent
/// stripe, a tinted background, and a matching icon — so the signal survives scrolling past
/// the section header. Blue (`colorScheme.secondary`) is reserved for actual links/actions
/// elsewhere in the app and is never used here, so it can't be confused with the attention cue.
///
/// The accent is a separate single-color `Container`, not part of the tile's border. A `Border`
/// whose sides use different colors combined with `borderRadius` is illegal in Flutter —
/// `Border.paint` only supports rounding when every side shares one color
/// (`box_border.dart`, `_distinctVisibleColors().length == 1`) — and throws/aborts painting the
/// whole decorated subtree otherwise. The tile's own border below is therefore always a single
/// uniform color; the accent lives in its own `Container` inside an `IntrinsicHeight`-sized
/// `Row` so it spans the tile's full height without a fixed height literal that could desync
/// from the (variable-height) text content.
class _EmailTile extends StatelessWidget {
  const _EmailTile({required this.summary});

  final EmailSummary summary;

  String _formatarDataRelativa(DateTime dt) {
    final agora = DateTime.now();
    final diferenca = agora.difference(dt);

    if (diferenca.inMinutes < 1) {
      return 'Agora';
    } else if (diferenca.inHours < 1) {
      return 'há ${diferenca.inMinutes}m';
    } else if (diferenca.inDays < 1) {
      return 'há ${diferenca.inHours}h';
    } else if (diferenca.inDays == 1) {
      return 'Ontem';
    } else if (diferenca.inDays < 7) {
      return 'há ${diferenca.inDays}d';
    } else {
      final dia = dt.day.toString().padLeft(2, '0');
      final mes = dt.month.toString().padLeft(2, '0');
      return '$dia/$mes';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final caution = context.sincroColors.caution;
    final pending = summary.precisaAtencao;

    // Pending tiles get a tinted caution background so they read as visually "lifted" from the
    // scaffold. Non-pending tiles need a real, visible surface too — `colorScheme.surface`
    // (0xFF1A1F23 in dark mode) is IDENTICAL to `scaffoldBackgroundColor` in dark mode
    // (theme.dart), so it's indistinguishable from the page background there.
    // `surfaceContainerHighest` is the token theme.dart defines explicitly and distinctly from
    // both scaffold colors in light (0xFFF5F5F5 vs 0xFFFAF8F5) and dark (0xFF2A2F35 vs
    // 0xFF1A1F23), so it's used here instead.
    final backgroundColor = pending ? caution.withValues(alpha: 0.08) : colors.surfaceContainerHighest;
    // Uniform single color on every side — never mixed with the accent color (see class doc).
    final perimeterBorderColor = pending ? caution.withValues(alpha: 0.3) : colors.outline;
    final accentColor = pending ? caution : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => EmailDetailScreen(summary: summary)),
          ),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            // Minimum touch target: 48dp
            constraints: const BoxConstraints(minHeight: 48),
            decoration: BoxDecoration(
              color: backgroundColor,
              border: Border.all(color: perimeterBorderColor, width: 1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Caution accent stripe. Single-color decoration (never mixed with the
                  // perimeter border), no fixed height — IntrinsicHeight + stretch size it to
                  // match the text column exactly, however tall that grows.
                  Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      // 16: theme.dart _spacing4, documented as "list item padding".
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Top row: sender (left, most emphasized) + timestamp (top-right,
                          // where mail clients conventionally place it) with the pending
                          // indicator next to it.
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  summary.remetente,
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: colors.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (pending) ...[
                                Icon(Icons.mark_email_unread_outlined, color: caution, size: 14),
                                const SizedBox(width: 4),
                              ],
                              // No alpha here: `subtitleColor.withValues(alpha: 0.8)` measured
                              // 3.28:1/3.57:1 (light) — below the 4.5:1 AA floor.
                              // `onSurfaceVariant` at full opacity measures 4.84:1/7.15:1.
                              Text(
                                _formatarDataRelativa(summary.recebidoEm),
                                style: textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Subject: primary text, boldest weight in the tile.
                          Text(
                            summary.assunto,
                            style: textTheme.bodyLarge?.copyWith(
                              color: colors.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          // Summary: regular weight, muted — the least emphasized of the four
                          // text elements, distinct from the semibold sender/subject above it.
                          Text(
                            summary.resumoCurto,
                            style: textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
