import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/widgets/section_card.dart';
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

// Idle border: ≥2.5:1 contra scaffold #FAF8F5 (light) / #1A1F23 (dark).
// Reusa os mesmos tokens já aprovados em AppInput e AppChip.
const Color _kBorderLight = Color(0xFF9C9690); // 2.76:1 vs #FAF8F5
const Color _kBorderDark = Color(0xFF66605A); // 2.68:1 vs #1A1F23

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
      // Best-effort, mesmo padrão de _registerFcmToken: uma falha aqui não deve travar a Home;
      // pior caso, o guia aparece de novo (ou deixa de aparecer) na próxima abertura.
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
      appBar: AppBar(
        title: const Text('Sincro'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Configurações',
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
        ],
      ),
      body: switch ((modo, design)) {
        (HomeLayoutMode.resumo, HomeDesignStyle.minimalista) =>
          const _HomeMinimalistaResumoView(),
        (HomeLayoutMode.resumo, HomeDesignStyle.moderno) =>
          const _HomeModernoResumoView(),
        (HomeLayoutMode.resumo, HomeDesignStyle.funcional) =>
          const _HomeFuncionalResumoView(),
        (HomeLayoutMode.abas, HomeDesignStyle.minimalista) =>
          const _HomeMinimalistaAbasView(),
        (HomeLayoutMode.abas, HomeDesignStyle.moderno) =>
          const _HomeModernoAbasView(),
        (HomeLayoutMode.abas, HomeDesignStyle.funcional) =>
          const _HomeFuncionalAbasView(),
      },
    );
  }
}

/// Botão de emergência + aviso de "sem contatos", compartilhado pelos dois layouts. No layout de
/// abas isso fica sempre visível, fora do `TabBarView` — a emergência precisa estar alcançável
/// independente de qual aba a pessoa está olhando.
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

class _HomeMinimalistaResumoView extends ConsumerWidget {
  const _HomeMinimalistaResumoView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gmailStatusAsync = ref.watch(gmailConnectionStatusProvider);
    final calendarEventsAsync = ref.watch(upcomingEventsProvider);
    final biofeedbackAtivoAsync = ref.watch(biofeedbackAtivoProvider);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Você está em dia', style: theme.textTheme.headlineMedium?.copyWith(fontSize: 24)),
                Text('Tudo sob controle', style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                const _FinancasHeroCard(),
                const SizedBox(height: 12),
                SectionCard(children: [
                  _GmailRow(statusAsync: gmailStatusAsync),
                  _CalendarRow(eventsAsync: calendarEventsAsync),
                  _BiofeedbackRow(ativoAsync: biofeedbackAtivoAsync),
                ]),
                const SizedBox(height: 12),
                const SectionCard(title: 'Apoio', children: [_ProfessionalsRow(), _GroundingCardsRow()]),
              ],
            ),
          ),
        ),
        const SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: _EmergencySection(),
          ),
        ),
      ],
    );
  }
}

class _RowIcon extends StatelessWidget {
  const _RowIcon(this.icon);
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: scheme.primary.withAlpha(26), borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, color: scheme.primary, size: 20),
    );
  }
}

class _GmailRow extends ConsumerWidget {
  const _GmailRow({required this.statusAsync});
  final AsyncValue<GmailConnectionStatus> statusAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return statusAsync.when(
      data: (status) {
        if (!status.connected) {
          return ListTile(
            leading: const _RowIcon(Icons.mail_outline),
            title: const Text('Caixa de Entrada'),
            subtitle: const Text(
              'Conecte seu Gmail para ver um resumo calmo dos seus e-mails.',
            ),
            trailing: ElevatedButton(
              onPressed: () => _conectarGmail(context, ref),
              child: const Text('Conectar Gmail'),
            ),
          );
        }
        return ListTile(
          leading: const _RowIcon(Icons.mail_outline),
          title: const Text('Caixa de Entrada'),
          subtitle: Text('Conectado como ${status.gmailEmail}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).pushNamed('/inbox'),
        );
      },
      loading: () => const ListTile(
        leading: _RowIcon(Icons.mail_outline),
        title: Text('Caixa de Entrada'),
        subtitle: Text('Carregando...'),
      ),
      error: (_, __) => const SizedBox.shrink(), // mesmo comportamento de _GmailCard hoje
    );
  }
}

class _CalendarRow extends ConsumerWidget {
  const _CalendarRow({required this.eventsAsync});
  final AsyncValue<List<CalendarEvent>> eventsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return eventsAsync.when(
      data: (events) {
        final upcomingThree = events.take(3).toList();
        return ListTile(
          leading: const _RowIcon(Icons.calendar_today_outlined),
          title: const Text('Próximos eventos'),
          subtitle: Text(
            upcomingThree.isEmpty
                ? 'Nenhum evento nos próximos dias'
                : '${upcomingThree.length} evento(s) agendado(s)',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).pushNamed('/calendar'),
        );
      },
      loading: () => const ListTile(
        leading: _RowIcon(Icons.calendar_today_outlined),
        title: Text('Próximos eventos'),
        subtitle: Text('Carregando...'),
      ),
      error: (_, __) => ListTile(
        leading: const _RowIcon(Icons.calendar_today_outlined),
        title: const Text('Próximos eventos'),
        subtitle: const Text('Conecte o Google Calendar para sincronizar'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).pushNamed('/calendar'),
      ),
    );
  }
}

class _BiofeedbackRow extends ConsumerWidget {
  const _BiofeedbackRow({required this.ativoAsync});
  final AsyncValue<bool> ativoAsync;

  Widget _rowInativo(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const _RowIcon(Icons.favorite_border),
      title: const Text('Biofeedback'),
      subtitle: const Text('Acompanhe seu bem-estar com seu smartwatch.'),
      trailing: OutlinedButton(
        onPressed: () => _ativarBiofeedback(context, ref),
        child: const Text('Ativar Biofeedback'),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ativoAsync.when(
      data: (ativo) {
        if (!ativo) return _rowInativo(context, ref);
        return ListTile(
          leading: const _RowIcon(Icons.favorite_border),
          title: const Text('Biofeedback'),
          subtitle: const _UltimaFcSubtitle(),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).pushNamed('/biofeedback'),
        );
      },
      loading: () => const ListTile(
        leading: _RowIcon(Icons.favorite_border),
        title: Text('Biofeedback'),
        subtitle: Text('Carregando...'),
      ),
      // O card do Biofeedback nunca some da Home (restrição global do pilar): se não deu para
      // ler o estado de ativação, mostramos a linha inativa, que continua sendo um ponto de
      // entrada válido — ativar de novo é idempotente.
      error: (_, __) => _rowInativo(context, ref),
    );
  }
}

class _ProfessionalsRow extends StatelessWidget {
  const _ProfessionalsRow();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const _RowIcon(Icons.medical_services_outlined),
      title: const Text('Encontrar profissional'),
      subtitle: const Text(
        'Busque profissionais neuroafirmativos perto de você.',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).pushNamed('/professionals'),
    );
  }
}

class _GroundingCardsRow extends StatelessWidget {
  const _GroundingCardsRow();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const _RowIcon(Icons.self_improvement_outlined),
      title: const Text('Alívio sensorial'),
      subtitle: const Text(
        'Técnicas de aterramento e alívio para o dia a dia.',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).pushNamed('/grounding-cards'),
    );
  }
}

/// Card calmo de Finanças na Home, versão "hero" do layout Resumo Simples minimalista: mesmo
/// resumo de saldo livre e pendências de `_FinancasCard`, num destaque visual maior (sem
/// `Card`/`ListTile`, com borda e fundo tonal) por ser o primeiro conteúdo da tela.
class _FinancasHeroCard extends ConsumerWidget {
  const _FinancasHeroCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final summaryAsync = ref.watch(financeSummaryProvider);
    final pendentes = _pendentesCount(ref);
    void abrir() => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FinancasScreen()),
        );

    final decoration = BoxDecoration(
      color: scheme.primary.withAlpha(15),
      border: Border.all(color: scheme.primary.withAlpha(64)),
      borderRadius: BorderRadius.circular(16),
    );

    return summaryAsync.when(
      loading: () => Container(
        decoration: decoration,
        padding: const EdgeInsets.all(16),
        child: const SizedBox(
          height: 96,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (_, __) => Container(
        decoration: decoration,
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: abrir,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Não foi possível carregar seu resumo agora. Toque para ver Finanças.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
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
              Text('Saldo Livre', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            Text(
              saldo,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontSize: 34,
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: pendentes != null && pendentes > 0
                    ? Text(
                        '$pendentes ${pendentes == 1 ? "lançamento" : "lançamentos"} para revisar, sem pressa',
                        style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                      )
                    : const SizedBox.shrink(),
              ),
              TextButton.icon(
                onPressed: abrir,
                icon: const Icon(Icons.arrow_forward, size: 18),
                iconAlignment: IconAlignment.end,
                label: const Text('Ver finanças'),
              ),
            ]),
          ],
        );
        return Container(
          decoration: decoration,
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: abrir,
              child: Padding(
                padding: const EdgeInsets.all(16),
                // Igual a `_FinancasCard` com `showTitle: false`: sem um título "Finanças"
                // visível neste cartão hero, a leitura por voz precisa dizer "Finanças"
                // explicitamente — sem isso começaria em "Saldo Livre" e só mencionaria
                // "Finanças" incidentalmente no "Ver finanças" do final.
                child: Semantics(
                  button: true,
                  label: _financasSemanticsLabel(saldo, pendentes),
                  excludeSemantics: true,
                  child: conteudo,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Layout alternativo para quem prefere mais informação organizada por contexto em vez de um
/// único scroll longo. Reusa exatamente os mesmos widgets de card do layout `resumo` — só muda o
/// agrupamento ao redor.
class _HomeMinimalistaAbasView extends ConsumerWidget {
  const _HomeMinimalistaAbasView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gmailStatusAsync = ref.watch(gmailConnectionStatusProvider);
    final calendarEventsAsync = ref.watch(upcomingEventsProvider);
    final biofeedbackAtivoAsync = ref.watch(biofeedbackAtivoProvider);

    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _FinancasCard(showTitle: false),
          ),
          const TabBar(
            tabs: [
              Tab(text: 'Hoje'),
              Tab(text: 'Apoio'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _GmailCard(statusAsync: gmailStatusAsync),
                    const SizedBox(height: 16),
                    _CalendarCard(eventsAsync: calendarEventsAsync),
                    const SizedBox(height: 16),
                    _BiofeedbackCard(ativoAsync: biofeedbackAtivoAsync),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: const [
                    _ProfessionalsCard(),
                    SizedBox(height: 16),
                    _GroundingCardsCard(),
                  ],
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: _EmergencySection(),
          ),
        ],
      ),
    );
  }
}

/// Extraído de `_GmailCard` (antes um método de instância `_connect`) para ser reutilizado por
/// `_GmailRow`, que reproduz o mesmo card no layout Resumo Simples minimalista sem o `Card`
/// envolvente.
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

class _GmailCard extends ConsumerWidget {
  const _GmailCard({required this.statusAsync});

  final AsyncValue<GmailConnectionStatus> statusAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return statusAsync.when(
      data: (status) {
        if (!status.connected) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.mail_outline),
              title: const Text('Caixa de Entrada'),
              subtitle: const Text(
                'Conecte seu Gmail para ver um resumo calmo dos seus e-mails.',
              ),
              trailing: ElevatedButton(
                onPressed: () => _conectarGmail(context, ref),
                child: const Text('Conectar Gmail'),
              ),
            ),
          );
        }
        return Card(
          child: ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('Caixa de Entrada'),
            subtitle: Text('Conectado como ${status.gmailEmail}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/inbox'),
          ),
        );
      },
      loading: () => const Card(
        child: ListTile(
          title: Text('Caixa de Entrada'),
          subtitle: Text('Carregando...'),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// Card calmo de Finanças na Home: uma prévia somente-leitura do saldo livre vindo de
/// `financeSummaryProvider`, que abre a tela completa ao ser tocado. Não há mais estado
/// "conectar conta" aqui — a conexão via e-mail acontece automaticamente no servidor.
class _FinancasCard extends ConsumerWidget {
  const _FinancasCard({this.showTitle = true});

  /// No layout Abas o card já se lê como uma prévia de valores à primeira vista (ícone + saldo),
  /// então a view de abas passa `false` aqui para tirar o título "Finanças" redundante. Quando
  /// `false`, o card ganha um `Semantics(excludeSemantics: true, ...)` explícito (ver `data:`
  /// abaixo) para que a leitura por voz continue anunciando "Finanças" mesmo sem o texto
  /// visível — não basta contar com o "Ver finanças →" incidental no fim do card.
  /// `excludeSemantics: true` substitui TODO o conteúdo anunciado do card pelo `label`, não só
  /// o título: por isso `_financasSemanticsLabel` inclui a contagem de pendências quando existe
  /// — sem isso, a linha "N lançamentos para revisar" continuaria visível na tela mas sumiria
  /// da leitura por voz. O layout Resumo Simples mantém o título (`true` por padrão), já que
  /// ali o card divide a tela com vários outros cards não relacionados e o título ajuda a
  /// diferenciá-los.
  final bool showTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(financeSummaryProvider);
    final pendentesCount = _pendentesCount(ref);

    return summaryAsync.when(
      loading: () => const Card(
        child: SizedBox(
          height: 96,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, stackTrace) => Card(
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const FinancasScreen()),
          ),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Não foi possível carregar seu resumo agora. Toque para ver Finanças.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ),
      data: (summary) {
        final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
        final saldoFormatado = currency.format(summary.saldoLivre);
        final conteudo = Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showTitle) ...[
                Text(
                  'Finanças',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
              ],
              Text(
                'Saldo Livre',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                saldoFormatado,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (pendentesCount != null && pendentesCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '$pendentesCount ${pendentesCount == 1 ? "lançamento" : "lançamentos"} para revisar, sem pressa',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                'Ver finanças →',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
        return Card(
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FinancasScreen()),
            ),
            borderRadius: BorderRadius.circular(16),
            child: showTitle
                ? conteudo
                // Sem o título visível, o rótulo de acessibilidade precisa dizer "Finanças"
                // explicitamente — sem isso, a leitura por voz começaria em "Saldo Livre" e só
                // mencionaria "Finanças" incidentalmente no "Ver finanças →" do final.
                : Semantics(
                    button: true,
                    label: _financasSemanticsLabel(saldoFormatado, pendentesCount),
                    excludeSemantics: true,
                    child: conteudo,
                  ),
          ),
        );
      },
    );
  }
}

/// Rótulo de acessibilidade do card de Finanças quando o título visível "Finanças" está
/// escondido (`showTitle: false`, layout Abas). `excludeSemantics: true` no `Semantics` que usa
/// este rótulo substitui TODO o conteúdo anunciado do card pelos nós filhos — inclusive a linha
/// "N lançamentos para revisar, sem pressa", que continua visível na tela mas desapareceria da
/// leitura por voz se não fosse incluída aqui explicitamente.
String _financasSemanticsLabel(String saldoFormatado, int? pendentesCount) {
  final base = 'Finanças — saldo livre $saldoFormatado';
  if (pendentesCount == null || pendentesCount <= 0) return base;
  final sufixo = pendentesCount == 1 ? 'lançamento' : 'lançamentos';
  return '$base, $pendentesCount $sufixo para revisar, sem pressa';
}

/// Contagem de pendências para o card calmo de Finanças da Home. Nice-to-have sobre o resumo
/// principal: se a lista de pendentes ainda está carregando ou falhou, cai em `null` (sem linha
/// de contagem) em vez de propagar um estado de erro/loading próprio.
int? _pendentesCount(WidgetRef ref) {
  return ref
      .watch(lancamentosPendentesProvider)
      .maybeWhen(data: (lista) => lista.length, orElse: () => null);
}

/// Extraído de `_BiofeedbackCard` (antes um método de instância `_ativar`) para ser reutilizado
/// por `_BiofeedbackRow`, que reproduz o mesmo card no layout Resumo Simples minimalista sem o
/// `Card` envolvente.
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

class _BiofeedbackCard extends ConsumerWidget {
  const _BiofeedbackCard({required this.ativoAsync});

  final AsyncValue<bool> ativoAsync;

  Widget _cardInativo(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.favorite_border),
        title: const Text('Biofeedback'),
        subtitle: const Text('Acompanhe seu bem-estar com seu smartwatch.'),
        trailing: ElevatedButton(
          onPressed: () => _ativarBiofeedback(context, ref),
          child: const Text('Ativar Biofeedback'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ativoAsync.when(
      data: (ativo) {
        if (!ativo) return _cardInativo(context, ref);
        return Card(
          child: ListTile(
            leading: const Icon(Icons.favorite_border),
            title: const Text('Biofeedback'),
            subtitle: const _UltimaFcSubtitle(),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/biofeedback'),
          ),
        );
      },
      loading: () => const Card(
        child: ListTile(
          title: Text('Biofeedback'),
          subtitle: Text('Carregando...'),
        ),
      ),
      // O card do Biofeedback nunca some da Home (restrição global do pilar): se não deu para
      // ler o estado de ativação, mostramos o card inativo, que continua sendo um ponto de
      // entrada válido — ativar de novo é idempotente.
      error: (_, __) => _cardInativo(context, ref),
    );
  }
}

/// Mostrada só quando o Biofeedback já está ativo (ver `_BiofeedbackCard.build`), então "nenhum
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
    final resumoAsync = ref.watch(biofeedbackResumoProvider);
    return resumoAsync.when(
      data: (resumo) {
        if (resumo?.ultimaFc == null) {
          return const Text('Nenhum dado disponível ainda');
        }
        // Sem "agora": a última leitura pode ter horas, já que a sincronização é periódica.
        final rotuloEstado = _rotuloEstado(resumo!.estadoEstresse);
        final texto = rotuloEstado.isEmpty
            ? '${resumo.ultimaFc!.round()} bpm'
            : '${resumo.ultimaFc!.round()} bpm · $rotuloEstado';
        return Text(texto);
      },
      loading: () => const Text('Carregando...'),
      error: (_, __) => const Text('Nenhum dado disponível ainda'),
    );
  }
}

class _NoContactsHint extends StatelessWidget {
  const _NoContactsHint();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
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

class _ProfessionalsCard extends StatelessWidget {
  const _ProfessionalsCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.medical_services_outlined),
        title: const Text('Encontrar profissional'),
        subtitle: const Text(
          'Busque profissionais neuroafirmativos perto de você.',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).pushNamed('/professionals'),
      ),
    );
  }
}

class _GroundingCardsCard extends StatelessWidget {
  const _GroundingCardsCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.self_improvement_outlined),
        title: const Text('Alívio sensorial'),
        subtitle: const Text(
          'Técnicas de aterramento e alívio para o dia a dia.',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).pushNamed('/grounding-cards'),
      ),
    );
  }
}

/// Moderno Suave: Design contemporâneo com ícones e gradientes sutis
class _HomeModernoResumoView extends ConsumerWidget {
  const _HomeModernoResumoView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gmailStatusAsync = ref.watch(gmailConnectionStatusProvider);
    final calendarEventsAsync = ref.watch(upcomingEventsProvider);
    final biofeedbackAtivoAsync = ref.watch(biofeedbackAtivoProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Você está em dia',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            'Tudo sob controle',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          const _ModernoFinancasCard(),
          const SizedBox(height: 11),
          _ModernoGmailCard(statusAsync: gmailStatusAsync),
          const SizedBox(height: 11),
          _ModernoCalendarCard(eventsAsync: calendarEventsAsync),
          const SizedBox(height: 11),
          _ModernoBiofeedbackCard(ativoAsync: biofeedbackAtivoAsync),
          const SizedBox(height: 11),
          _ModernoProfessionalsCard(),
          const SizedBox(height: 11),
          _ModernoGroundingCardsCard(),
          const SizedBox(height: 20),
          const _EmergencySection(),
        ],
      ),
    );
  }
}

class _HomeModernoAbasView extends ConsumerWidget {
  const _HomeModernoAbasView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gmailStatusAsync = ref.watch(gmailConnectionStatusProvider);
    final calendarEventsAsync = ref.watch(upcomingEventsProvider);
    final biofeedbackAtivoAsync = ref.watch(biofeedbackAtivoProvider);

    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: _ModernoFinancasCard(showTitle: false),
          ),
          const TabBar(
            tabs: [
              Tab(text: 'Hoje'),
              Tab(text: 'Apoio'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    _ModernoGmailCard(statusAsync: gmailStatusAsync),
                    const SizedBox(height: 11),
                    _ModernoCalendarCard(eventsAsync: calendarEventsAsync),
                    const SizedBox(height: 11),
                    _ModernoBiofeedbackCard(ativoAsync: biofeedbackAtivoAsync),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    _ModernoProfessionalsCard(),
                    const SizedBox(height: 11),
                    _ModernoGroundingCardsCard(),
                  ],
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(14),
            child: _EmergencySection(),
          ),
        ],
      ),
    );
  }
}

class _ModernoGmailCard extends ConsumerWidget {
  const _ModernoGmailCard({required this.statusAsync});

  final AsyncValue<GmailConnectionStatus> statusAsync;

  Future<void> _connect(BuildContext context, WidgetRef ref) async {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return statusAsync.when(
      data: (status) {
        if (!status.connected) {
          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.blue.withAlpha(25),
                    Colors.cyan.withAlpha(15),
                  ],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListTile(
                leading: Icon(Icons.mail_outline, color: Colors.blue[600]),
                title: const Text('Caixa de Entrada'),
                subtitle: const Text(
                  'Conecte seu Gmail para ver um resumo calmo dos seus e-mails.',
                ),
                trailing: ElevatedButton(
                  onPressed: () => _connect(context, ref),
                  child: const Text('Conectar Gmail'),
                ),
              ),
            ),
          );
        }
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ListTile(
            leading: Icon(Icons.mail_outline, color: Colors.blue[600]),
            title: const Text('Caixa de Entrada'),
            subtitle: Text('Conectado como ${status.gmailEmail}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/inbox'),
          ),
        );
      },
      loading: () => Card(
        elevation: 0,
        child: ListTile(
          title: const Text('Caixa de Entrada'),
          subtitle: const Text('Carregando...'),
          leading: Icon(Icons.mail_outline, color: Colors.blue[600]),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// Card calmo de Finanças na Home (design Moderno): mesma prévia de saldo livre de
/// `_FinancasCard`, com o gradiente sutil característico deste estilo. Ver o doc de
/// `_FinancasCard` para o porquê de não haver mais estado "conectar conta" aqui.
class _ModernoFinancasCard extends ConsumerWidget {
  const _ModernoFinancasCard({this.showTitle = true});

  /// Ver `_FinancasCard.showTitle`: a view de abas passa `false` para tirar o título "Finanças"
  /// redundante. Quando `false`, o card ganha um `Semantics` explícito (ver `data:` abaixo) para
  /// que a leitura por voz continue anunciando "Finanças" mesmo sem o texto visível.
  final bool showTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(financeSummaryProvider);
    final pendentesCount = _pendentesCount(ref);

    return summaryAsync.when(
      loading: () => const Card(
        elevation: 0,
        child: SizedBox(
          height: 96,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, stackTrace) => Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const FinancasScreen()),
          ),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Não foi possível carregar seu resumo agora. Toque para ver Finanças.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ),
      data: (summary) {
        final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
        final saldoFormatado = currency.format(summary.saldoLivre);
        final conteudo = Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.green.withAlpha(25),
                Colors.teal.withAlpha(15),
              ],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showTitle) ...[
                Text(
                  'Finanças',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Icon(
                    Icons.account_balance_outlined,
                    color: Colors.green[600],
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Saldo Livre',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                saldoFormatado,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (pendentesCount != null && pendentesCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '$pendentesCount ${pendentesCount == 1 ? "lançamento" : "lançamentos"} para revisar, sem pressa',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                'Ver finanças →',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FinancasScreen()),
            ),
            borderRadius: BorderRadius.circular(8),
            child: showTitle
                ? conteudo
                : Semantics(
                    button: true,
                    label: _financasSemanticsLabel(saldoFormatado, pendentesCount),
                    excludeSemantics: true,
                    child: conteudo,
                  ),
          ),
        );
      },
    );
  }
}

class _ModernoBiofeedbackCard extends ConsumerWidget {
  const _ModernoBiofeedbackCard({required this.ativoAsync});

  final AsyncValue<bool> ativoAsync;

  Future<void> _ativar(BuildContext context, WidgetRef ref) async {
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
      await ref.read(biofeedbackCacheProvider).setAtivo(true);
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
      } catch (_) {}
      ref.invalidate(biofeedbackAtivoProvider);
      ref.invalidate(biofeedbackResumoProvider);
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ativoAsync.when(
      data: (ativo) {
        if (!ativo) {
          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.red.withAlpha(25), Colors.pink.withAlpha(15)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListTile(
                leading: Icon(Icons.favorite_border, color: Colors.red[600]),
                title: const Text('Biofeedback'),
                subtitle: const Text(
                  'Acompanhe seu bem-estar com seu smartwatch.',
                ),
                trailing: ElevatedButton(
                  onPressed: () => _ativar(context, ref),
                  child: const Text('Ativar Biofeedback'),
                ),
              ),
            ),
          );
        }
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ListTile(
            leading: Icon(Icons.favorite_border, color: Colors.red[600]),
            title: const Text('Biofeedback'),
            subtitle: const _UltimaFcSubtitle(),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/biofeedback'),
          ),
        );
      },
      loading: () => Card(
        elevation: 0,
        child: ListTile(
          title: const Text('Biofeedback'),
          subtitle: const Text('Carregando...'),
          leading: Icon(Icons.favorite_border, color: Colors.red[600]),
        ),
      ),
      error: (_, __) => Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.red.withAlpha(25), Colors.pink.withAlpha(15)],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListTile(
            leading: Icon(Icons.favorite_border, color: Colors.red[600]),
            title: const Text('Biofeedback'),
            subtitle: const Text('Acompanhe seu bem-estar com seu smartwatch.'),
            trailing: ElevatedButton(
              onPressed: () => _ativar(context, ref),
              child: const Text('Ativar Biofeedback'),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModernoProfessionalsCard extends StatelessWidget {
  const _ModernoProfessionalsCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primary.withAlpha(25),
              Theme.of(context).colorScheme.secondary.withAlpha(15),
            ],
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          leading: Icon(
            Icons.medical_services_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: const Text('Encontrar profissional'),
          subtitle: const Text(
            'Busque profissionais neuroafirmativos perto de você.',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).pushNamed('/professionals'),
        ),
      ),
    );
  }
}

class _ModernoGroundingCardsCard extends StatelessWidget {
  const _ModernoGroundingCardsCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.orange.withAlpha(25), Colors.amber.withAlpha(15)],
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          leading: Icon(
            Icons.self_improvement_outlined,
            color: Colors.deepOrange[700],
          ),
          title: const Text('Alívio sensorial'),
          subtitle: const Text(
            'Técnicas de aterramento e alívio para o dia a dia.',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).pushNamed('/grounding-cards'),
        ),
      ),
    );
  }
}

/// Funcional Direto: Máxima clareza visual, layout tipo lista compacto
class _HomeFuncionalResumoView extends ConsumerWidget {
  const _HomeFuncionalResumoView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gmailStatusAsync = ref.watch(gmailConnectionStatusProvider);
    final calendarEventsAsync = ref.watch(upcomingEventsProvider);
    final biofeedbackAtivoAsync = ref.watch(biofeedbackAtivoProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Monitorando seu ritmo',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          const _FuncionalFinancasCard(),
          const SizedBox(height: 16),
          _FuncionalStatusSummary(),
          const SizedBox(height: 16),
          Text('CONEXÕES', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 8),
          _FuncionalGmailCard(statusAsync: gmailStatusAsync),
          const SizedBox(height: 8),
          _FuncionalCalendarCard(eventsAsync: calendarEventsAsync),
          const SizedBox(height: 8),
          _FuncionalBiofeedbackCard(ativoAsync: biofeedbackAtivoAsync),
          const SizedBox(height: 16),
          Text('RECURSOS', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 8),
          _FuncionalProfessionalsCard(),
          const SizedBox(height: 8),
          _FuncionalGroundingCardsCard(),
          const SizedBox(height: 16),
          const _EmergencySection(),
        ],
      ),
    );
  }
}

class _HomeFuncionalAbasView extends ConsumerWidget {
  const _HomeFuncionalAbasView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gmailStatusAsync = ref.watch(gmailConnectionStatusProvider);
    final calendarEventsAsync = ref.watch(upcomingEventsProvider);
    final biofeedbackAtivoAsync = ref.watch(biofeedbackAtivoProvider);

    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: _FuncionalFinancasCard(showTitle: false),
          ),
          const TabBar(
            tabs: [
              Tab(text: 'Hoje'),
              Tab(text: 'Apoio'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _FuncionalStatusSummary(),
                    const SizedBox(height: 12),
                    _FuncionalGmailCard(statusAsync: gmailStatusAsync),
                    const SizedBox(height: 8),
                    _FuncionalCalendarCard(eventsAsync: calendarEventsAsync),
                    const SizedBox(height: 8),
                    _FuncionalBiofeedbackCard(
                      ativoAsync: biofeedbackAtivoAsync,
                    ),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _FuncionalProfessionalsCard(),
                    const SizedBox(height: 8),
                    _FuncionalGroundingCardsCard(),
                  ],
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: _EmergencySection(),
          ),
        ],
      ),
    );
  }
}

class _FuncionalStatusSummary extends ConsumerWidget {
  const _FuncionalStatusSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
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
    final iconColor = biofeedbackAsync.when<Color>(
      data: (v) => v ? Colors.green[700]! : colorScheme.onSurfaceVariant,
      loading: () => colorScheme.onSurfaceVariant,
      error: (_, __) => colorScheme.onSurfaceVariant,
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.brightness == Brightness.light
              ? _kBorderLight
              : _kBorderDark,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Status do dia', style: theme.textTheme.labelMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FuncionalGmailCard extends ConsumerWidget {
  const _FuncionalGmailCard({required this.statusAsync});

  final AsyncValue<GmailConnectionStatus> statusAsync;

  Future<void> _connect(BuildContext context, WidgetRef ref) async {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return statusAsync.when(
      data: (status) {
        if (!status.connected) {
          return Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.light
                    ? _kBorderLight
                    : _kBorderDark,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.mail_outline, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Email',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const Text('Conectar', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: () => _connect(context, ref),
                  child: const Text('Conectar'),
                ),
              ],
            ),
          );
        }
        final emailLabel = status.gmailEmail ?? 'Email não disponível';
        return Semantics(
          button: true,
          excludeSemantics: true,
          label: 'Email — $emailLabel',
          onTap: () => Navigator.of(context).pushNamed('/inbox'),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pushNamed('/inbox'),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.light
                        ? _kBorderLight
                        : _kBorderDark,
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.mail_outline, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Email',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            emailLabel,
                            style: const TextStyle(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.check_circle,
                      size: 20,
                      color: Colors.green[700],
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      loading: () => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.light
                ? _kBorderLight
                : _kBorderDark,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            Icon(Icons.mail_outline, size: 20),
            SizedBox(width: 10),
            Expanded(child: Text('Email')),
          ],
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// Card calmo de Finanças na Home (design Funcional): mesma prévia de saldo livre de
/// `_FinancasCard`, com o chrome compacto e bordado deste estilo. Ver o doc de `_FinancasCard`
/// para o porquê de não haver mais estado "conectar conta" aqui.
class _FuncionalFinancasCard extends ConsumerWidget {
  const _FuncionalFinancasCard({this.showTitle = true});

  /// Ver `_FinancasCard.showTitle`. Diferente dos cards Minimalista/Moderno, este já carrega um
  /// `Semantics(label: 'Finanças — ...')` explícito em volta de toda a área tocável (abaixo),
  /// então esconder o texto visível "Finanças" não muda em nada o que a leitura por voz anuncia
  /// — só o título redundante na tela é que desaparece.
  final bool showTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(financeSummaryProvider);
    final pendentesCount = _pendentesCount(ref);

    return summaryAsync.when(
      loading: () => const SizedBox(
        height: 96,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Semantics(
        button: true,
        excludeSemantics: true,
        label: 'Finanças — não foi possível carregar seu resumo agora',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FinancasScreen()),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const FinancasScreen()),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.light
                      ? _kBorderLight
                      : _kBorderDark,
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Não foi possível carregar seu resumo agora. Toque para ver Finanças.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ),
      data: (summary) {
        final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
        final saldoFormatado = currency.format(summary.saldoLivre);
        return Semantics(
          button: true,
          excludeSemantics: true,
          label: _financasSemanticsLabel(saldoFormatado, pendentesCount),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const FinancasScreen()),
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FinancasScreen()),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.light
                        ? _kBorderLight
                        : _kBorderDark,
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_balance_outlined, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showTitle)
                            const Text(
                              'Finanças',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                          Text(
                            'Saldo livre: $saldoFormatado',
                            style: const TextStyle(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (pendentesCount != null && pendentesCount > 0)
                            Text(
                              '$pendentesCount ${pendentesCount == 1 ? "lançamento" : "lançamentos"} para revisar, sem pressa',
                              style: const TextStyle(fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          Text(
                            'Ver finanças →',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FuncionalBiofeedbackCard extends ConsumerWidget {
  const _FuncionalBiofeedbackCard({required this.ativoAsync});

  final AsyncValue<bool> ativoAsync;

  Future<void> _ativar(BuildContext context, WidgetRef ref) async {
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
      await ref.read(biofeedbackCacheProvider).setAtivo(true);
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
      } catch (_) {}
      ref.invalidate(biofeedbackAtivoProvider);
      ref.invalidate(biofeedbackResumoProvider);
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ativoAsync.when(
      data: (ativo) {
        if (!ativo) {
          return Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.light
                    ? _kBorderLight
                    : _kBorderDark,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.favorite_border, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Biofeedback',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const Text('Ativar', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: () => _ativar(context, ref),
                  child: const Text('Ativar'),
                ),
              ],
            ),
          );
        }
        return Semantics(
          button: true,
          excludeSemantics: true,
          label: 'Biofeedback ativo',
          onTap: () => Navigator.of(context).pushNamed('/biofeedback'),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pushNamed('/biofeedback'),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.light
                        ? _kBorderLight
                        : _kBorderDark,
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.favorite_border, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Biofeedback',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          DefaultTextStyle.merge(
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            child: const _UltimaFcSubtitle(),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.check_circle,
                      size: 20,
                      color: Colors.green[700],
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      loading: () => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.light
                ? _kBorderLight
                : _kBorderDark,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            Icon(Icons.favorite_border, size: 20),
            SizedBox(width: 10),
            Expanded(child: Text('Biofeedback')),
          ],
        ),
      ),
      error: (_, __) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.light
                ? _kBorderLight
                : _kBorderDark,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.favorite_border, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Biofeedback',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const Text('Ativar', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () => _ativar(context, ref),
              child: const Text('Ativar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FuncionalProfessionalsCard extends StatelessWidget {
  const _FuncionalProfessionalsCard();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: 'Profissionais',
      onTap: () => Navigator.of(context).pushNamed('/professionals'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pushNamed('/professionals'),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.light
                    ? _kBorderLight
                    : _kBorderDark,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.medical_services_outlined, size: 20),
                const SizedBox(width: 10),
                const Expanded(child: Text('Profissionais')),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FuncionalGroundingCardsCard extends StatelessWidget {
  const _FuncionalGroundingCardsCard();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: 'Alívio sensorial',
      onTap: () => Navigator.of(context).pushNamed('/grounding-cards'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pushNamed('/grounding-cards'),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.light
                    ? _kBorderLight
                    : _kBorderDark,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.self_improvement_outlined, size: 20),
                const SizedBox(width: 10),
                const Expanded(child: Text('Alívio sensorial')),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// CALENDAR CARDS (Minimalista, Moderno, Funcional)
// ============================================================================

/// Card simples do calendário (design minimalista):
/// Mostra os próximos 3 eventos com título + horário e botão para ver calendário completo.
class _CalendarCard extends ConsumerWidget {
  const _CalendarCard({required this.eventsAsync});

  final AsyncValue<List<CalendarEvent>> eventsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return eventsAsync.when(
      data: (events) {
        final upcomingThree = events.take(3).toList();
        return Card(
          child: ListTile(
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('Próximos eventos'),
            subtitle: Text(
              upcomingThree.isEmpty
                  ? 'Nenhum evento nos próximos dias'
                  : '${upcomingThree.length} evento(s) agendado(s)',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/calendar'),
          ),
        );
      },
      loading: () => const Card(
        child: ListTile(
          title: Text('Próximos eventos'),
          subtitle: Text('Carregando...'),
          leading: Icon(Icons.calendar_today_outlined),
        ),
      ),
      error: (_, __) => Card(
        child: ListTile(
          leading: const Icon(Icons.calendar_today_outlined),
          title: const Text('Próximos eventos'),
          subtitle: const Text('Conecte o Google Calendar para sincronizar'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).pushNamed('/calendar'),
        ),
      ),
    );
  }
}

/// Card do calendário (design moderno com gradiente):
/// Versão com gradiente sutil (padrão do design moderno).
class _ModernoCalendarCard extends ConsumerWidget {
  const _ModernoCalendarCard({required this.eventsAsync});

  final AsyncValue<List<CalendarEvent>> eventsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return eventsAsync.when(
      data: (events) {
        final upcomingThree = events.take(3).toList();
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.primary.withAlpha(25),
                  colorScheme.secondary.withAlpha(15),
                ],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListTile(
              leading: Icon(
                Icons.calendar_today_outlined,
                color: colorScheme.primary,
              ),
              title: const Text('Próximos eventos'),
              subtitle: Text(
                upcomingThree.isEmpty
                    ? 'Nenhum evento nos próximos dias'
                    : '${upcomingThree.length} evento(s) agendado(s)',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).pushNamed('/calendar'),
            ),
          ),
        );
      },
      loading: () => Card(
        elevation: 0,
        child: ListTile(
          title: const Text('Próximos eventos'),
          subtitle: const Text('Carregando...'),
          leading: Icon(
            Icons.calendar_today_outlined,
            color: colorScheme.primary,
          ),
        ),
      ),
      error: (_, __) => Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.primary.withAlpha(25),
                colorScheme.secondary.withAlpha(15),
              ],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListTile(
            leading: Icon(
              Icons.calendar_today_outlined,
              color: colorScheme.primary,
            ),
            title: const Text('Próximos eventos'),
            subtitle: const Text('Conecte o Google Calendar para sincronizar'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/calendar'),
          ),
        ),
      ),
    );
  }
}

/// Card do calendário (design funcional):
/// Versão compacta com border, sem gradiente ou decorações extras.
class _FuncionalCalendarCard extends ConsumerWidget {
  const _FuncionalCalendarCard({required this.eventsAsync});

  final AsyncValue<List<CalendarEvent>> eventsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return eventsAsync.when(
      data: (events) {
        final upcomingThree = events.take(3).toList();
        final calLabel = upcomingThree.isEmpty
            ? 'Calendário — nenhum evento'
            : 'Calendário — ${upcomingThree.length} evento(s)';
        return Semantics(
          button: true,
          excludeSemantics: true,
          label: calLabel,
          onTap: () => Navigator.of(context).pushNamed('/calendar'),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pushNamed('/calendar'),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.light
                        ? _kBorderLight
                        : _kBorderDark,
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Calendário',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            upcomingThree.isEmpty
                                ? 'Nenhum evento'
                                : '${upcomingThree.length} evento(s)',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      loading: () => Semantics(
        button: true,
        excludeSemantics: true,
        label: 'Calendário — carregando',
        onTap: () => Navigator.of(context).pushNamed('/calendar'),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).pushNamed('/calendar'),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.light
                      ? _kBorderLight
                      : _kBorderDark,
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.calendar_today_outlined, size: 20),
                  SizedBox(width: 10),
                  Expanded(child: Text('Calendário')),
                ],
              ),
            ),
          ),
        ),
      ),
      error: (_, __) => Semantics(
        button: true,
        excludeSemantics: true,
        label: 'Calendário — ver mais',
        onTap: () => Navigator.of(context).pushNamed('/calendar'),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).pushNamed('/calendar'),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.light
                      ? _kBorderLight
                      : _kBorderDark,
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Calendário')),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
