import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/section_row.dart';
import '../../core/widgets/tonal_panel.dart';
import '../trusted_contacts/trusted_contacts_providers.dart';
import '../email_triage/email_triage_providers.dart';
import '../email_triage/gmail_connection_repository.dart';
import '../biofeedback/biofeedback_cache.dart';
import '../biofeedback/biofeedback_providers.dart';
import '../biofeedback/estado_estresse.dart';
import '../calendar/calendar_providers.dart';
import '../calendar/calendar_event.dart';
import '../financas/finance_providers.dart';
import '../financas/financas_screen.dart';
import '../guide/guide_content.dart';
import '../guide/guide_providers.dart';
import '../guide/guide_screen.dart';
import 'emergency_button.dart';
import 'home_layout_mode.dart';
import 'home_design_style.dart';
import 'home_providers.dart';

// Borda forte do estilo Funcional Direto: ≥2.5:1 contra scaffold #FAF8F5 (light) / #1A1F23
// (dark). Reusa os mesmos tokens já aprovados em AppInput e AppChip. Os outros dois estilos
// usam `colorScheme.outline`, como na prancha da direção A.
const Color _kBorderLight = Color(0xFF9C9690); // 2.76:1 vs #FAF8F5
const Color _kBorderDark = Color(0xFF66605A); // 2.68:1 vs #1A1F23

/// Traços que distinguem os três estilos de design dentro da mesma estrutura da direção A.
///
/// A estrutura (saudação, cartão de destaque de Finanças, cartões agrupados, "Apoio", rodapé
/// fixo de emergência) é a mesma nas seis combinações; o que muda é o "temperamento" visual:
/// - Minimalista Refinado: tonal chapado, respiro generoso — a prancha "Home · A" ao pé da letra.
/// - Moderno Suave: mesma malha, com degradês sutis nos tiles e no cartão de destaque.
/// - Funcional Direto: linhas mais densas (48 dp, ícone simples), borda mais forte, títulos em
///   todos os grupos e uma linha "Status do dia" — tudo visível, nada implícito.
extension _HomeStyleX on HomeDesignStyle {
  bool get dense => this == HomeDesignStyle.funcional;
  bool get gradient => this == HomeDesignStyle.moderno;

  double get pagePadding => dense ? 16 : 20;
  double get gap => dense ? 8 : 12;

  Color? borderColor(BuildContext context) {
    if (!dense) return null;
    return Theme.of(context).brightness == Brightness.light ? _kBorderLight : _kBorderDark;
  }

  /// Rótulo do primeiro grupo de linhas. Só o Funcional nomeia tudo; nos outros dois a saudação
  /// e o cartão de destaque já contextualizam o grupo.
  String? get primeiroGrupoTitulo => dense ? 'Hoje' : null;
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerFcmToken();
      _checkGuide();
    });
  }

  Future<void> _registerFcmToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token != null) {
        await ref.read(fcmTokenRepositoryProvider).register(token);
      }
    } catch (_) {
      // Registro de notificação é best-effort: o app continua funcionando
      // normalmente mesmo se o dispositivo não conseguir registrar o token
      // (ex: emulador sem Google Play Services, permissão negada).
    }
  }

  Future<void> _checkGuide() async {
    try {
      final versaoVista = await ref
          .read(guidePreferenceProvider)
          .getVersaoVista();
      final pendentes = itemsToShow(guideItems, versaoVista);
      if (pendentes.isEmpty || !mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GuideScreen(
            items: pendentes,
            title: versaoVista == 0 ? 'Guia rápido do Sincro' : 'Novidades',
          ),
        ),
      );
      if (mounted) {
        await ref.read(guidePreferenceProvider).setVersaoVista(guiaVersaoAtual);
      }
    } catch (_) {
      // Guia é best-effort: se a preferência falhar, o app segue normalmente.
    }
  }

  @override
  Widget build(BuildContext context) {
    // Sem spinner na tela principal: `resumo` já é o próprio default do provider, então cair
    // nele enquanto a preferência carrega não troca de layout visivelmente depois.
    final modo = ref
        .watch(homeLayoutModeProvider)
        .maybeWhen(data: (m) => m, orElse: () => HomeLayoutMode.resumo);

    final design = ref
        .watch(homeDesignStyleProvider)
        .maybeWhen(data: (d) => d, orElse: () => HomeDesignStyle.minimalista);

    return Scaffold(
      // Cabeçalho da prancha Home·A: logo 24 dp + wordmark "Sincro" 14 bold em onSurfaceVariant.
      appBar: AppBar(
        toolbarHeight: 48,
        titleSpacing: 20,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/logos/symbol_transparent_512x512.png',
              width: 24,
              height: 24,
              excludeFromSemantics: true,
            ),
            const SizedBox(width: 8),
            Text(
              'Sincro',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Configurações',
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
        ],
      ),
      body: switch (modo) {
        HomeLayoutMode.resumo => _HomeResumoView(style: design),
        HomeLayoutMode.abas => _HomeAbasView(style: design),
      },
    );
  }
}

// ============================================================================
// LAYOUTS (Resumo simples / Abas) — mesma estrutura da direção A nos três estilos
// ============================================================================

/// Resumo simples: um único scroll com saudação, cartão de destaque de Finanças e os cartões
/// agrupados; o rodapé de emergência fica fixo fora da rolagem, sempre alcançável.
class _HomeResumoView extends ConsumerWidget {
  const _HomeResumoView({required this.style});

  final HomeDesignStyle style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = style.pagePadding;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(p, 4, p, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _HomeGreeting(),
                SizedBox(height: style.gap),
                _FinancasHeroCard(style: style),
                SizedBox(height: style.gap),
                _HojeSectionCard(style: style),
                SizedBox(height: style.gap),
                _ApoioSectionCard(style: style),
              ],
            ),
          ),
        ),
        _EmergencyFooter(style: style),
      ],
    );
  }
}

/// Abas: saudação e cartão de destaque de Finanças fixos acima das abas "Hoje" / "Apoio", que
/// mostram os mesmos cartões agrupados do Resumo; o rodapé de emergência continua fixo, fora do
/// `TabBarView`, para ser alcançável de qualquer aba.
class _HomeAbasView extends ConsumerWidget {
  const _HomeAbasView({required this.style});

  final HomeDesignStyle style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = style.pagePadding;
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            // Saudação e cartão de destaque rolam junto com o conteúdo das abas (a TabBar fica
            // fixa no topo ao rolar). Com o cabeçalho fixo acima de um Expanded, em texto grande
            // (textScaler 2.0) o TabBarView ficava com altura zero e as abas apareciam vazias.
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(p, 4, p, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _HomeGreeting(),
                        SizedBox(height: style.gap),
                        _FinancasHeroCard(style: style),
                      ],
                    ),
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _PinnedTabBarDelegate(
                    backgroundColor: theme.scaffoldBackgroundColor,
                    tabBar: const TabBar(
                      tabs: [
                        Tab(text: 'Hoje'),
                        Tab(text: 'Apoio'),
                      ],
                    ),
                  ),
                ),
              ],
              body: TabBarView(
                children: [
                  ListView(
                    padding: EdgeInsets.all(p),
                    children: [_HojeSectionCard(style: style, showTitle: false)],
                  ),
                  ListView(
                    padding: EdgeInsets.all(p),
                    children: [_ApoioSectionCard(style: style, showTitle: false)],
                  ),
                ],
              ),
            ),
          ),
          _EmergencyFooter(style: style),
        ],
      ),
    );
  }
}

/// Mantém a `TabBar` fixa no topo enquanto o cabeçalho (saudação + cartão de destaque) rola.
class _PinnedTabBarDelegate extends SliverPersistentHeaderDelegate {
  const _PinnedTabBarDelegate({required this.tabBar, required this.backgroundColor});

  final TabBar tabBar;
  final Color backgroundColor;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(color: backgroundColor, child: tabBar);
  }

  @override
  bool shouldRebuild(_PinnedTabBarDelegate oldDelegate) =>
      oldDelegate.tabBar != tabBar || oldDelegate.backgroundColor != backgroundColor;
}

/// Saudação da direção A: título 24 bold + subtítulo 14 em `onSurfaceVariant`.
class _HomeGreeting extends StatelessWidget {
  const _HomeGreeting();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Você está em dia', style: theme.textTheme.headlineMedium?.copyWith(fontSize: 24)),
        Text(
          'Tudo sob controle',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Grupo "Hoje": Caixa de Entrada, Próximos eventos e Biofeedback. No Funcional ganha título e a
/// linha "Status do dia" no topo.
class _HojeSectionCard extends ConsumerWidget {
  const _HojeSectionCard({required this.style, this.showTitle = true});

  final HomeDesignStyle style;

  /// Nas abas o próprio nome da aba já rotula o grupo — sem título repetido.
  final bool showTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gmailStatusAsync = ref.watch(gmailConnectionStatusProvider);
    final calendarEventsAsync = ref.watch(upcomingEventsProvider);
    final biofeedbackAtivoAsync = ref.watch(biofeedbackAtivoProvider);
    return SectionCard(
      title: showTitle ? style.primeiroGrupoTitulo : null,
      borderColor: style.borderColor(context),
      children: [
        if (style.dense) const _StatusRow(),
        _GmailRow(statusAsync: gmailStatusAsync, style: style),
        _CalendarRow(eventsAsync: calendarEventsAsync, style: style),
        _BiofeedbackRow(ativoAsync: biofeedbackAtivoAsync, style: style),
      ],
    );
  }
}

/// Grupo "Apoio": Encontrar profissional e Alívio sensorial.
class _ApoioSectionCard extends StatelessWidget {
  const _ApoioSectionCard({required this.style, this.showTitle = true});

  final HomeDesignStyle style;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: showTitle ? 'Apoio' : null,
      borderColor: style.borderColor(context),
      children: [
        _ProfessionalsRow(style: style),
        _GroundingCardsRow(style: style),
      ],
    );
  }
}

/// Rodapé fixo (fora da rolagem) com o botão de emergência e o aviso de "sem contatos".
class _EmergencyFooter extends StatelessWidget {
  const _EmergencyFooter({required this.style});

  final HomeDesignStyle style;

  @override
  Widget build(BuildContext context) {
    final p = style.pagePadding;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(p, 8, p, 8),
        child: const _EmergencySection(),
      ),
    );
  }
}

/// Botão de emergência + aviso de "sem contatos", compartilhado pelos dois layouts. Fica sempre
/// visível, fora do scroll e do `TabBarView` — a emergência precisa estar alcançável independente
/// de onde a pessoa está olhando.
class _EmergencySection extends ConsumerWidget {
  const _EmergencySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(trustedContactsListProvider);
    return contactsAsync.when(
      data: (contacts) {
        if (contacts.isEmpty) {
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _NoContactsHint(),
              SizedBox(height: 16),
              EmergencyButton(),
            ],
          );
        }
        return const EmergencyButton();
      },
      loading: () => const EmergencyButton(),
      error: (_, __) => const EmergencyButton(),
    );
  }
}

// ============================================================================
// LINHAS DOS CARTÕES AGRUPADOS
// ============================================================================

/// Cor de destaque por linha no estilo Moderno Suave (nos outros estilos tudo é `primary`).
/// Só cores do `ColorScheme`, para funcionar nos dois temas.
Color? _accent(BuildContext context, HomeDesignStyle style, Color Function(ColorScheme) pick) {
  if (!style.gradient) return null;
  return pick(Theme.of(context).colorScheme);
}


/// Ação secundária compacta no `trailing` de uma linha (selo de duas linhas da prancha, ~96 dp):
/// um botão de uma linha ("Ativar Biofeedback", 165 dp) esmagava a coluna de texto e quebrava o
/// título no meio da palavra em 390 dp. `dense` (Funcional) usa o rótulo curto de uma linha.
Widget _compactAction(BuildContext context, {required String label, required VoidCallback onPressed, bool filled = false}) {
  final style = ButtonStyle(
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
    minimumSize: const WidgetStatePropertyAll(Size(64, 44)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textStyle: WidgetStatePropertyAll(
      Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
  final text = Text(label, textAlign: TextAlign.center, softWrap: true);
  return ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 96),
    child: filled
        ? ElevatedButton(style: style, onPressed: onPressed, child: text)
        : OutlinedButton(style: style, onPressed: onPressed, child: text),
  );
}

/// Indicador de estado do Funcional Direto ("tudo visível"): check verde quando o item está
/// conectado/ativo, antes do chevron.
Widget _denseTrailing(BuildContext context, {required bool ok}) {
  final scheme = Theme.of(context).colorScheme;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (ok) ...[
        Icon(Icons.check_circle, size: 20, color: context.sincroColors.success),
        const SizedBox(width: 4),
      ],
      Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
    ],
  );
}

/// Linha "Status do dia" do Funcional Direto: monitoramento do Biofeedback ativo ou não.
class _StatusRow extends ConsumerWidget {
  const _StatusRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final biofeedbackAsync = ref.watch(biofeedbackAtivoProvider);
    final label = biofeedbackAsync.when(
      data: (v) => v ? 'Monitoramento ativo' : 'Monitoramento inativo',
      loading: () => 'Verificando...',
      error: (_, __) => 'Dados indisponíveis',
    );
    final icon = biofeedbackAsync.when(
      data: (v) => v ? Icons.check_circle : Icons.circle_outlined,
      loading: () => Icons.hourglass_empty_outlined,
      error: (_, __) => Icons.error_outline,
    );
    final iconColor = biofeedbackAsync.maybeWhen<Color>(
      data: (v) => v ? context.sincroColors.success : scheme.onSurfaceVariant,
      orElse: () => scheme.onSurfaceVariant,
    );
    return SectionRow(
      dense: true,
      leading: Icon(icon, size: 20, color: iconColor),
      title: 'Status do dia',
      subtitle: label,
    );
  }
}

class _GmailRow extends ConsumerWidget {
  const _GmailRow({required this.statusAsync, required this.style});

  final AsyncValue<GmailConnectionStatus> statusAsync;
  final HomeDesignStyle style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = _accent(context, style, (s) => s.secondary);
    return statusAsync.when(
      data: (status) {
        if (!status.connected) {
          return SectionRow(
            icon: Icons.mail_outline,
            accent: accent,
            dense: style.dense,
            gradient: style.gradient,
            title: 'Caixa de Entrada',
            subtitle: style.dense
                ? 'Conectar Gmail'
                : 'Conecte seu Gmail para ver um resumo calmo dos seus e-mails.',
            trailing: _compactAction(
              context,
              label: style.dense ? 'Conectar' : 'Conectar\nGmail',
              filled: true,
              onPressed: () => _conectarGmail(context, ref),
            ),
          );
        }
        final email = status.gmailEmail ?? 'E-mail não disponível';
        return SectionRow(
          icon: Icons.mail_outline,
          accent: accent,
          dense: style.dense,
          gradient: style.gradient,
          title: 'Caixa de Entrada',
          // Funcional: só o dado, sem prosa — a linha inteira já diz "Caixa de Entrada".
          subtitle: style.dense ? email : 'Conectado como $email',
          trailing: style.dense ? _denseTrailing(context, ok: true) : null,
          onTap: () => Navigator.of(context).pushNamed('/inbox'),
        );
      },
      loading: () => SectionRow(
        icon: Icons.mail_outline,
        accent: accent,
        dense: style.dense,
        gradient: style.gradient,
        title: 'Caixa de Entrada',
        subtitle: 'Carregando...',
      ),
      error: (_, __) => const SizedBox.shrink(), // mesmo comportamento histórico do card de Gmail
    );
  }
}

class _CalendarRow extends ConsumerWidget {
  const _CalendarRow({required this.eventsAsync, required this.style});

  final AsyncValue<List<CalendarEvent>> eventsAsync;
  final HomeDesignStyle style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = _accent(context, style, (s) => s.primary);
    void abrir() => Navigator.of(context).pushNamed('/calendar');
    return eventsAsync.when(
      data: (events) {
        final upcomingThree = events.take(3).toList();
        final subtitle = upcomingThree.isEmpty
            ? (style.dense ? 'Nenhum evento' : 'Nenhum evento nos próximos dias')
            : (style.dense
                ? '${upcomingThree.length} evento(s)'
                : '${upcomingThree.length} evento(s) agendado(s)');
        return SectionRow(
          icon: Icons.calendar_today_outlined,
          accent: accent,
          dense: style.dense,
          gradient: style.gradient,
          title: 'Próximos eventos',
          subtitle: subtitle,
          onTap: abrir,
        );
      },
      loading: () => SectionRow(
        icon: Icons.calendar_today_outlined,
        accent: accent,
        dense: style.dense,
        gradient: style.gradient,
        title: 'Próximos eventos',
        subtitle: 'Carregando...',
      ),
      error: (_, __) => SectionRow(
        icon: Icons.calendar_today_outlined,
        accent: accent,
        dense: style.dense,
        gradient: style.gradient,
        title: 'Próximos eventos',
        subtitle: 'Conecte o Google Calendar para sincronizar',
        onTap: abrir,
      ),
    );
  }
}

class _BiofeedbackRow extends ConsumerWidget {
  const _BiofeedbackRow({required this.ativoAsync, required this.style});

  final AsyncValue<bool> ativoAsync;
  final HomeDesignStyle style;

  Widget _rowInativo(BuildContext context, WidgetRef ref, Color? accent) {
    return SectionRow(
      icon: Icons.favorite_border,
      accent: accent,
      dense: style.dense,
      gradient: style.gradient,
      title: 'Biofeedback',
      subtitle: style.dense ? 'Ativar monitoramento' : 'Acompanhe seu bem-estar com seu smartwatch.',
      trailing: _compactAction(
        context,
        label: style.dense ? 'Ativar' : 'Ativar\nBiofeedback',
        onPressed: () => _ativarBiofeedback(context, ref),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = _accent(context, style, (s) => s.tertiary);
    return ativoAsync.when(
      data: (ativo) {
        if (!ativo) return _rowInativo(context, ref, accent);
        return SectionRow(
          icon: Icons.favorite_border,
          accent: accent,
          dense: style.dense,
          gradient: style.gradient,
          title: 'Biofeedback',
          subtitleWidget: const _UltimaFcSubtitle(),
          trailing: style.dense ? _denseTrailing(context, ok: true) : null,
          onTap: () => Navigator.of(context).pushNamed('/biofeedback'),
        );
      },
      loading: () => SectionRow(
        icon: Icons.favorite_border,
        accent: accent,
        dense: style.dense,
        gradient: style.gradient,
        title: 'Biofeedback',
        subtitle: 'Carregando...',
      ),
      // O card do Biofeedback nunca some da Home (restrição global do pilar): se não deu para
      // ler o estado de ativação, mostramos a linha inativa, que continua sendo um ponto de
      // entrada válido — ativar de novo é idempotente.
      error: (_, __) => _rowInativo(context, ref, accent),
    );
  }
}

class _ProfessionalsRow extends StatelessWidget {
  const _ProfessionalsRow({required this.style});

  final HomeDesignStyle style;

  @override
  Widget build(BuildContext context) {
    return SectionRow(
      icon: Icons.medical_services_outlined,
      accent: _accent(context, style, (s) => s.primary),
      dense: style.dense,
      gradient: style.gradient,
      title: 'Encontrar profissional',
      subtitle: 'Busque profissionais neuroafirmativos perto de você.',
      onTap: () => Navigator.of(context).pushNamed('/professionals'),
    );
  }
}

class _GroundingCardsRow extends StatelessWidget {
  const _GroundingCardsRow({required this.style});

  final HomeDesignStyle style;

  @override
  Widget build(BuildContext context) {
    return SectionRow(
      icon: Icons.self_improvement_outlined,
      accent: _accent(context, style, (s) => s.secondary),
      dense: style.dense,
      gradient: style.gradient,
      title: 'Alívio sensorial',
      subtitle: 'Técnicas de aterramento e alívio para o dia a dia.',
      onTap: () => Navigator.of(context).pushNamed('/grounding-cards'),
    );
  }
}

// ============================================================================
// CARTÃO DE DESTAQUE DE FINANÇAS
// ============================================================================

/// Cartão de destaque de Finanças da direção A: painel tonal com "Saldo Livre", o valor em
/// 34 sp `primary`, a contagem calma de pendências e o link "Ver finanças". É o primeiro
/// conteúdo da tela nos dois layouts e nos três estilos:
/// - Moderno: degradê sutil no fundo;
/// - Funcional: mais compacto (valor em 28 sp) e com a borda forte do estilo.
///
/// Sem um título "Finanças" visível, a leitura por voz precisa dizer "Finanças" explicitamente
/// — por isso o `Semantics(excludeSemantics: true, label: ...)` em volta do conteúdo.
class _FinancasHeroCard extends ConsumerWidget {
  const _FinancasHeroCard({required this.style});

  final HomeDesignStyle style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final summaryAsync = ref.watch(financeSummaryProvider);
    final pendentes = _pendentesCount(ref);
    void abrir() => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FinancasScreen()),
        );
    final padding = EdgeInsets.all(style.dense ? 12 : 16);

    return summaryAsync.when(
      loading: () => TonalPanel(
        gradient: style.gradient,
        borderColor: style.borderColor(context),
        padding: padding,
        child: const SizedBox(
          height: 96,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (_, __) => TonalPanel(
        gradient: style.gradient,
        borderColor: style.borderColor(context),
        padding: padding,
        onTap: abrir,
        child: Text(
          'Não foi possível carregar seu resumo agora. Toque para ver Finanças.',
          style: theme.textTheme.bodySmall,
        ),
      ),
      data: (summary) {
        final saldo = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(summary.saldoLivre);
        final conteudo = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.account_balance_outlined, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              // Flexible: em texto grande (2,0×) o rótulo precisa quebrar, não estourar a linha.
              Flexible(
                child: Text('Saldo Livre', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              saldo,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontSize: style.dense ? 28 : 34,
                height: 1.1,
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: pendentes != null && pendentes > 0
                      ? Text(
                          '$pendentes ${pendentes == 1 ? "lançamento" : "lançamentos"} para revisar, sem pressa',
                          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        )
                      : const SizedBox.shrink(),
                ),
                // Link inline (não um botão): o cartão inteiro já é o alvo de toque, e um botão
                // aqui criaria um segundo nó de acessibilidade dentro do `Semantics` de cima.
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            'Ver finanças',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward, size: 18, color: scheme.primary),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
        return TonalPanel(
          gradient: style.gradient,
          borderColor: style.borderColor(context),
          padding: padding,
          onTap: abrir,
          child: Semantics(
            button: true,
            label: _financasSemanticsLabel(saldo, pendentes),
            excludeSemantics: true,
            child: conteudo,
          ),
        );
      },
    );
  }
}

/// Rótulo de acessibilidade do cartão de Finanças. `excludeSemantics: true` no `Semantics` que
/// usa este rótulo substitui TODO o conteúdo anunciado do cartão — inclusive a linha "N
/// lançamentos para revisar, sem pressa", que continua visível na tela mas desapareceria da
/// leitura por voz se não fosse incluída aqui explicitamente.
String _financasSemanticsLabel(String saldoFormatado, int? pendentesCount) {
  final base = 'Finanças — saldo livre $saldoFormatado';
  if (pendentesCount == null || pendentesCount <= 0) return base;
  final sufixo = pendentesCount == 1 ? 'lançamento' : 'lançamentos';
  return '$base, $pendentesCount $sufixo para revisar, sem pressa';
}

/// Contagem de pendências para o cartão de Finanças da Home. Nice-to-have sobre o resumo
/// principal: se a lista de pendentes ainda está carregando ou falhou, cai em `null` (sem linha
/// de contagem) em vez de propagar um estado de erro/loading próprio.
int? _pendentesCount(WidgetRef ref) {
  return ref
      .watch(lancamentosPendentesProvider)
      .maybeWhen(data: (lista) => lista.length, orElse: () => null);
}

// ============================================================================
// AÇÕES E AUXILIARES COMPARTILHADOS
// ============================================================================

Future<void> _conectarGmail(BuildContext context, WidgetRef ref) async {
  try {
    await ref.read(gmailConnectionRepositoryProvider).connect();
    ref.invalidate(gmailConnectionStatusProvider);
  } catch (e, st) {
    debugPrint('❌ Gmail connection failed: $e');
    debugPrintStack(stackTrace: st);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível conectar o Gmail. Tente novamente.',
          ),
        ),
      );
    }
  }
}

Future<void> _ativarBiofeedback(BuildContext context, WidgetRef ref) async {
  try {
    final autorizado = await ref
        .read(biofeedbackHealthServiceProvider)
        .solicitarPermissao();
    if (!autorizado) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Permissão não concedida. Você pode tentar novamente quando quiser.',
            ),
          ),
        );
      }
      return;
    }
    // Persistimos a ativação e agendamos o background ANTES da primeira sincronização: se a
    // primeira leitura falhar (Health Connect ainda inicializando, nenhuma fonte de dados
    // pareada, chamada instável), a permissão já foi concedida e não faz sentido obrigar o
    // usuário a refazer tudo. O agendamento em background cuida das próximas tentativas.
    await ref.read(biofeedbackCacheProvider).setAtivo(true);
    // A ativação já pediu TODAS as permissões da versão atual (`_tipos` inclui passos e
    // treinos), então registramos a versão aqui para que a checagem de upgrade dentro de
    // `sincronizar()` seja um no-op para quem está ativando agora — em vez de pedir de novo,
    // sem motivo, logo na primeira sincronização.
    await ref
        .read(biofeedbackCacheProvider)
        .setPermissoesVersao(BiofeedbackCache.versaoPermissoesAtual);
    final frequenciaMinutos = await ref
        .read(biofeedbackCacheProvider)
        .getFrequenciaMinutos();
    await ref
        .read(biofeedbackBackgroundTaskProvider)
        .registrar(Duration(minutes: frequenciaMinutos));
    try {
      await ref.read(biofeedbackSyncServiceProvider).sincronizar();
    } catch (_) {
      // Primeira sincronização é best-effort — mesma postura do callback do background.
    }
    ref.invalidate(biofeedbackAtivoProvider);
    ref.invalidate(biofeedbackResumoProvider);
    // A sincronização acima também grava o histórico de repouso, que alimenta o contador
    // "(N de 7 dias)" da tela de detalhe.
    ref.invalidate(biofeedbackDiasNoHistoricoProvider);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível ativar o Biofeedback. Tente novamente.',
          ),
        ),
      );
    }
  }
}

/// Mostrada só quando o Biofeedback já está ativo (ver `_BiofeedbackRow.build`), então "nenhum
/// dado disponível ainda" aqui significa "ativado mas sem smartwatch pareado", não "não ativado".
class _UltimaFcSubtitle extends ConsumerWidget {
  const _UltimaFcSubtitle();

  static String _rotuloEstado(EstadoEstresse estado) {
    switch (estado) {
      case EstadoEstresse.calmo:
        return 'Calmo';
      case EstadoEstresse.elevado:
        return 'Elevado';
      case EstadoEstresse.coletandoDados:
        // Não menciona "coletando dados" na Home — a tela de detalhe é o lugar para isso, para
        // a Home (primeiro contato do app) não parecer ter uma pendência.
        return '';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final resumoAsync = ref.watch(biofeedbackResumoProvider);
    return resumoAsync.when(
      data: (resumo) {
        if (resumo?.ultimaFc == null) {
          return Text('Nenhum dado disponível ainda', style: style);
        }
        // Sem "agora": a última leitura pode ter horas, já que a sincronização é periódica.
        final rotuloEstado = _rotuloEstado(resumo!.estadoEstresse);
        final texto = rotuloEstado.isEmpty
            ? '${resumo.ultimaFc!.round()} bpm'
            : '${resumo.ultimaFc!.round()} bpm · $rotuloEstado';
        return Text(texto, style: style);
      },
      loading: () => Text('Carregando...', style: style),
      error: (_, __) => Text('Nenhum dado disponível ainda', style: style),
    );
  }
}

class _NoContactsHint extends StatelessWidget {
  const _NoContactsHint();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: colors.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Adicione um contato de confiança para estar preparado em emergências.',
                style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
