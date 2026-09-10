import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import 'email_detail_screen.dart';
import 'email_summary.dart';
import 'email_triage_providers.dart';
import 'gmail_connection_actions.dart';
import 'gmail_connection_repository.dart';

// Calibrated against scaffold AND card fills in both themes.
// #7C7672: L≈0.185 → 4.22:1 vs #FAF8F5, 3.77:1 vs #F1EBE1 (light fills);
//                       3.73:1 vs #1A1F23, 3.02:1 vs #2A2F35, 3.18:1 vs #2C2B26 (dark fills).
const Color _kBorderLight = Color(0xFF7C7672);
const Color _kBorderDark = Color(0xFF7C7672);

/// Ações disponíveis no menu de "mais ações" de cada e-mail da caixa de entrada.
enum _AcaoEmailTile { arquivar, excluir }

class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summariesAsync = ref.watch(emailSummariesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Caixa de Entrada'),
        // A conexão com o Gmail é gerenciada aqui — não só em Configurações — porque é aqui que
        // a pessoa percebe que precisa reconectar (para conceder o escopo `gmail.modify`) ou que
        // quer desconectar. Um menu de "mais opções" na AppBar não disputa espaço com o conteúdo
        // da lista, que é o motivo de a pessoa estar nesta tela.
        actions: const [_GmailConnectionMenu()],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(emailSummariesProvider),
        child: summariesAsync.when(
          data: (summaries) {
            if (summaries.isEmpty) {
              return const _EmptyState();
            }
            final precisamAtencao = summaries
                .where((s) => s.precisaAtencao)
                .toList();
            final podemEsperar = summaries
                .where((s) => !s.precisaAtencao)
                .toList();

            final items = <_InboxListItem>[
              if (precisamAtencao.isNotEmpty) ...[
                _InboxListItem.header(
                  'Precisam de atenção',
                  precisamAtencao.length,
                  isPending: true,
                ),
                ...precisamAtencao.map(_InboxListItem.email),
              ],
              if (podemEsperar.isNotEmpty) ...[
                _InboxListItem.header(
                  'Podem esperar',
                  podemEsperar.length,
                  isPending: false,
                ),
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

enum _AcaoMenuConexaoGmail { permitirModificacao, desconectar, reconectar }

/// Menu de "mais opções" da conexão com o Gmail, na AppBar da caixa de entrada.
///
/// Sempre mostra pelo menos uma ação, para nunca deixar a pessoa sem um caminho de volta:
///   - Conectado, mas ainda sem o escopo `gmail.modify` (contas que conectaram antes desse
///     escopo existir): destaca "Permitir arquivar e excluir e-mails", que reconecta e concede o
///     escopo que falta — a mesma ação que hoje só aparece reativamente, via SnackBar, quando uma
///     tentativa de arquivar/excluir falha com 403.
///   - Conectado: "Desconectar Gmail", com confirmação (ver `confirmarEDesconectarGmail`).
///   - Não conectado (ou status desconhecido, por exemplo se a checagem falhar): "Reconectar
///     Gmail", para que desconectar por aqui nunca seja uma porta sem volta dentro do mesmo fluxo.
class _GmailConnectionMenu extends ConsumerWidget {
  const _GmailConnectionMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(gmailConnectionStatusProvider);

    return statusAsync.when(
      data: (status) => _menu(context, ref, status),
      loading: () => const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      // Status desconhecido (checagem falhou): trata como "não conectado" para o menu — a única
      // ação seguramente correta nesse caso é oferecer reconectar, nunca esconder o menu inteiro.
      error: (_, __) => _menu(context, ref, null),
    );
  }

  Widget _menu(BuildContext context, WidgetRef ref, GmailConnectionStatus? status) {
    final conectado = status?.connected ?? false;
    final semEscopoModificacao = conectado && !(status?.temEscopoModificacao ?? false);

    return PopupMenuButton<_AcaoMenuConexaoGmail>(
      tooltip: 'Opções da conexão com o Gmail',
      icon: const Icon(Icons.more_vert),
      onSelected: (acao) {
        switch (acao) {
          case _AcaoMenuConexaoGmail.permitirModificacao:
          case _AcaoMenuConexaoGmail.reconectar:
            _reconectar(context, ref, avisarSucesso: acao == _AcaoMenuConexaoGmail.permitirModificacao);
          case _AcaoMenuConexaoGmail.desconectar:
            _desconectar(context, ref);
        }
      },
      itemBuilder: (context) => [
        if (semEscopoModificacao)
          const PopupMenuItem(
            value: _AcaoMenuConexaoGmail.permitirModificacao,
            child: Text('Permitir arquivar e excluir e-mails'),
          ),
        if (conectado)
          const PopupMenuItem(
            value: _AcaoMenuConexaoGmail.desconectar,
            child: Text('Desconectar Gmail'),
          ),
        if (!conectado)
          const PopupMenuItem(
            value: _AcaoMenuConexaoGmail.reconectar,
            child: Text('Reconectar Gmail'),
          ),
      ],
    );
  }

  Future<void> _desconectar(BuildContext context, WidgetRef ref) async {
    final desconectou = await confirmarEDesconectarGmail(context, ref);
    // A caixa de entrada depende diretamente da conexão: sem invalidar a lista, ela continuaria
    // mostrando e-mails que o backend acabou de apagar junto com a conexão.
    if (desconectou) {
      ref.invalidate(emailSummariesProvider);
    }
  }

  Future<void> _reconectar(BuildContext context, WidgetRef ref, {required bool avisarSucesso}) async {
    final status = await reconectarGmail(context, ref);
    if (status == null) return; // erro já mostrado por reconectarGmail

    if (!avisarSucesso) {
      // Reconexão "cheia" (a partir de desconectado): a caixa de entrada precisa recarregar,
      // independentemente do escopo de modificação — é o caminho de leitura que estava faltando.
      ref.invalidate(emailSummariesProvider);
      return;
    }
    if (!context.mounted) return;

    // Só anuncia sucesso depois de RELER o status e confirmar o escopo — `connect()` não ter
    // lançado não prova que a pessoa concedeu `gmail.modify`: o consentimento do Google é
    // granular e ela pode ter desmarcado esse escopo específico na tela de login.
    if (status.temEscopoModificacao) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gmail reconectado. Agora você pode arquivar e excluir e-mails por aqui.'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A conexão foi feita, mas a permissão para arquivar e excluir e-mails não foi '
            'concedida. Você pode tentar de novo e, na tela do Google, deixar essa permissão '
            'marcada.',
          ),
        ),
      );
    }
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
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
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
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
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

    final badgeColor = isPending
        ? sincroColors.caution
        : colors.onSurfaceVariant;

    return Semantics(
      header: true,
      child: Padding(
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
              // No border: the filled background already communicates the category, and a
              // translucent border (`badgeColor.withValues(alpha: 0.3)`, ~1.54:1) fails the 3:1
              // floor required for non-text UI. Omitting it is safer than another opacity guess.
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
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
///
/// This is a `ConsumerStatefulWidget` (not stateless) for two reasons: the keyboard focus ring
/// needs to react to `onFocusChange` with `setState` — there's no way to know, at build time,
/// whether this specific tile is focused without local state — and the archive/delete actions
/// below need `ref` to reach [emailSummaryRepositoryProvider] and, on a missing-scope failure,
/// [gmailConnectionRepositoryProvider]/[gmailConnectionStatusProvider]. The ring reuses
/// `colorScheme.primary` as an opaque 2dp border (same pattern as `_DayCell` in
/// calendar_screen.dart) instead of the default `InkWell` `focusColor`, whose low alpha over
/// these tinted backgrounds measured ~1.30:1 — far below the 3:1 floor for non-text UI
/// indicators.
class _EmailTile extends ConsumerStatefulWidget {
  const _EmailTile({required this.summary});

  final EmailSummary summary;

  @override
  ConsumerState<_EmailTile> createState() => _EmailTileState();
}

class _EmailTileState extends ConsumerState<_EmailTile> {
  bool _focado = false;

  /// Arquivar é imediato (sem confirmação): a Gmail API só remove o label INBOX — a mensagem
  /// continua inteira e pode ser encontrada em "Todos os e-mails" no próprio Gmail — então o
  /// SnackBar informativo abaixo já é feedback suficiente; não há uma ação de "desfazer" própria
  /// porque restaurá-la ainda é trivial pelo Gmail em si.
  Future<void> _arquivar() async {
    final id = widget.summary.id;
    try {
      await ref.read(emailSummaryRepositoryProvider).arquivar(id);
      if (!mounted) return;
      ref.invalidate(emailSummariesProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('E-mail arquivado.')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 403) {
        _mostrarReconectar('Reconecte o Gmail para arquivar e-mails por aqui.');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível arquivar agora. Tente novamente.')),
        );
      }
    }
  }

  /// Excluir move a mensagem para a lixeira do Gmail (recuperável por lá por ~30 dias) — nunca
  /// uma exclusão permanente — mas ainda é uma ação destrutiva o bastante para pedir confirmação
  /// antes de agir, em vez de oferecer desfazer depois.
  Future<void> _confirmarExclusao() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir e-mail?'),
        content: const Text(
          'O e-mail vai para a lixeira do Gmail, onde continua recuperável por cerca de 30 dias.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    await _excluir();
  }

  Future<void> _excluir() async {
    final id = widget.summary.id;
    try {
      await ref.read(emailSummaryRepositoryProvider).excluir(id);
      if (!mounted) return;
      ref.invalidate(emailSummariesProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('E-mail movido para a lixeira.')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 403) {
        _mostrarReconectar('Reconecte o Gmail para excluir e-mails por aqui.');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível excluir agora. Tente novamente.')),
        );
      }
    }
  }

  /// Chamado quando o backend responde 403 por falta do escopo `gmail.modify` — em vez de falhar
  /// em silêncio, mostra o caminho de reconexão diretamente no SnackBar da ação que falhou.
  void _mostrarReconectar(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        action: SnackBarAction(label: 'Reconectar', onPressed: _reconectar),
      ),
    );
  }

  // Reutiliza a mesma ação de reconexão do menu da AppBar (gmail_connection_actions.dart) em vez
  // de repetir a chamada ao repositório + invalidação do status.
  //
  // `avisarSucesso: true` porque aqui a pessoa já estava conectada e veio de um 403 ao arquivar
  // ou excluir: ela pediu justamente a permissão que faltava, então precisa saber se desta vez
  // foi concedida. Sem isso o caminho fica mudo e ela pode cair no laço 403 → "Reconectar" → 403
  // sem entender por quê — que é exatamente o que o menu da AppBar já evita.
  Future<void> _reconectar() async {
    await reconectarGmailEAvisar(context, ref, avisarSucesso: true);
  }

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
    final summary = widget.summary;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final textTheme = theme.textTheme;
    final caution = context.sincroColors.caution;
    final pending = summary.precisaAtencao;

    // Pending tiles get a tinted caution background so they read as visually "lifted" from the
    // scaffold. Non-pending tiles need a real, visible surface too — `colorScheme.surface`
    // (0xFF1A1F23 in dark mode) is IDENTICAL to `scaffoldBackgroundColor` in dark mode
    // (theme.dart), so it's indistinguishable from the page background there.
    // `surfaceContainerHighest` is the token theme.dart defines explicitly and distinctly from
    // both scaffold colors in light (0xFFF5F5F5 vs 0xFFFAF8F5) and dark (0xFF2A2F35 vs
    // 0xFF1A1F23), so it's used here instead.
    final backgroundColor = pending
        ? caution.withValues(alpha: 0.08)
        : colors.surfaceContainerHighest;
    // Idle border: always `_kBorderLight`/`_kBorderDark`, for both the plain and pending states.
    // `colorScheme.outline` measured 1.25:1 and `caution.withValues(alpha: 0.3)` measured 1.68:1
    // — both fail the 2.5:1 floor for a container border. The caution accent stripe already
    // carries the urgency signal, so the perimeter border doesn't need to repeat it.
    final idleBorderColor = theme.brightness == Brightness.light
        ? _kBorderLight
        : _kBorderDark;
    final accentColor = pending ? caution : Colors.transparent;

    void abrirDetalhe() => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EmailDetailScreen(summary: summary)),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        // Minimum touch target: 48dp
        constraints: const BoxConstraints(minHeight: 48),
        // Clips all children (including the accent stripe below) to this container's rounded
        // rectangle shape. Without this, the accent stripe — a sibling of the InkWell, not
        // itself bounded by the card's RRect — overflows the card's 12dp corners: its own
        // `Radius.circular(12)` gets clamped down to ~2dp anyway (Flutter clamps a decoration's
        // corner radii when they sum to more than the box's width: 12+12=24 > the stripe's
        // 4dp width), so it could never match the card's corner even un-clipped.
        clipBehavior: Clip.antiAlias,
        // Fill color lives in `decoration` (doesn't consume the child's space). The border
        // lives in `foregroundDecoration` instead: `Container` deducts a `decoration` border's
        // width from the space available to its child, but does not do so for
        // `foregroundDecoration` — without this split, the 1-2dp border would shrink the
        // tappable `InkWell` area below the 48dp floor.
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
        ),
        foregroundDecoration: BoxDecoration(
          border: Border.all(
            color: _focado ? colors.primary : idleBorderColor,
            width: _focado ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          color: Colors.transparent,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Caution accent stripe. Single-color decoration (never mixed with the
                // perimeter border), no fixed height — IntrinsicHeight + stretch size it to
                // match the text column exactly, however tall that grows. No borderRadius
                // here: the outer Container's `clipBehavior: Clip.antiAlias` already clips
                // this stripe to the card's 12dp corners.
                Container(width: 4, color: accentColor),
                // The "open e-mail" tap target is scoped to just this Expanded column (not the
                // whole card) so the trailing "mais ações" button below can live as an
                // independent, separately-announced Semantics node in the same Row. Wrapping the
                // *entire* row (as before) in one `excludeSemantics: true` Semantics node would
                // swallow the action button's own semantics along with everything else under it.
                Expanded(
                  child: Semantics(
                    button: true,
                    label:
                        '${summary.assunto} de ${summary.remetente} '
                        '${_formatarDataRelativa(summary.recebidoEm)}, '
                        '${summary.resumoCurto}, '
                        '${pending ? "precisa de atenção" : "pode esperar"}',
                    onTap: abrirDetalhe,
                    excludeSemantics: true,
                    child: InkWell(
                      onTap: abrirDetalhe,
                      onFocusChange: (focado) => setState(() => _focado = focado),
                      focusColor: Colors.transparent,
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
                                  Icon(
                                    Icons.mark_email_unread_outlined,
                                    color: caution,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                // No alpha here: `subtitleColor.withValues(alpha: 0.8)` measured
                                // 3.28:1/3.57:1 (light) — below the 4.5:1 AA floor.
                                // `onSurfaceVariant` at full opacity measures 4.84:1/7.15:1.
                                Text(
                                  _formatarDataRelativa(summary.recebidoEm),
                                  style: textTheme.labelSmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
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
                              style: textTheme.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // "Mais ações" (arquivar/excluir): a 48x48 touch target of its own, reachable by
                // keyboard/screen reader independently of the "abrir e-mail" tap target above —
                // never a swipe-only gesture, which wouldn't be discoverable or accessible.
                SizedBox(
                  width: 48,
                  child: Center(
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: PopupMenuButton<_AcaoEmailTile>(
                        tooltip: 'Mais ações',
                        icon: const Icon(Icons.more_vert),
                        onSelected: (acao) {
                          switch (acao) {
                            case _AcaoEmailTile.arquivar:
                              _arquivar();
                            case _AcaoEmailTile.excluir:
                              _confirmarExclusao();
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: _AcaoEmailTile.arquivar,
                            child: Text('Arquivar'),
                          ),
                          PopupMenuItem(
                            value: _AcaoEmailTile.excluir,
                            child: Text('Excluir'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
