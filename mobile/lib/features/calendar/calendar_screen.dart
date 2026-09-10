import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/app_input.dart';
import '../email_triage/email_triage_providers.dart';
import '../email_triage/gmail_connection_repository.dart';
import 'calendar_providers.dart';
import 'calendar_event.dart';
import 'calendar_repository.dart';

/// Intervalo mínimo entre revalidações automáticas ao retomar o app (ver
/// `didChangeAppLifecycleState` em [_CalendarScreenState]). Cobre o caso relatado — usuário cria
/// ou edita um evento no calendário nativo do aparelho e volta ao Sincro — sem refazer as duas
/// chamadas de rede a cada troca trivial de app (notificação, teclado, um app diferente por
/// alguns segundos). 30s é curto o bastante para o usuário nunca perceber os dados como
/// desatualizados no fluxo relatado (sair do Sincro, abrir o calendário do aparelho, criar/editar
/// um evento, voltar — isso raramente leva menos de 30s) e longo o bastante para não gerar uma
/// rajada de requisições em quem alterna de app repetidamente em poucos segundos.
const Duration _kRevalidationMinInterval = Duration(seconds: 30);

// Idle border: ≥2.5:1 contra scaffold #FAF8F5 (light) / #1A1F23 (dark).
// Mesmos tokens já aprovados em AppInput, AppChip e HomeScreen.
const Color _kBorderLight = Color(0xFF9C9690); // 2.76:1 vs #FAF8F5
const Color _kBorderDark = Color(0xFF66605A); // 2.68:1 vs #1A1F23

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen>
    with WidgetsBindingObserver {
  late int _currentYear;
  late int _currentMonth;

  // `null` só antes da primeira revalidação; inicializado em [initState] porque a tela já busca
  // dados frescos ao ser criada — não há motivo para revalidar de novo se o app for retomado
  // (`resumed`) menos de [_kRevalidationMinInterval] depois da tela ter acabado de abrir.
  DateTime? _lastRevalidatedAt;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentYear = now.year;
    _currentMonth = now.month;
    _lastRevalidatedAt = now;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Cobre o sintoma relatado: usuário cria/edita um evento no app de calendário nativo do
  // aparelho e volta ao Sincro. Sem isso, os providers `autoDispose` só refazem a busca quando a
  // tela é recriada do zero — nunca ao simplesmente retomar o app com a tela já aberta.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) return;
    final agora = DateTime.now();
    final ultima = _lastRevalidatedAt;
    if (ultima != null &&
        agora.difference(ultima) < _kRevalidationMinInterval) {
      return;
    }
    _lastRevalidatedAt = agora;
    ref.invalidate(upcomingEventsProvider);
    ref.invalidate(monthEventsProvider);
  }

  // Usado tanto pelo gesto de puxar-para-atualizar quanto poderia ser reusado por qualquer botão
  // de atualização manual futuro. Invalida os dois providers e só resolve quando as novas buscas
  // terminam (sucesso ou erro), para que o `RefreshIndicator` mostre o spinner pelo tempo certo.
  // Erros não são relançados: já ficam visíveis via `AsyncValue.error` nos painéis correspondentes
  // — deixar a exceção escapar daqui só produziria um erro não tratado sem nenhum usuário para vê-lo.
  Future<void> _atualizar() async {
    _lastRevalidatedAt = DateTime.now();
    ref.invalidate(upcomingEventsProvider);
    ref.invalidate(monthEventsProvider);
    try {
      await Future.wait([
        ref.read(upcomingEventsProvider.future),
        ref.read(monthEventsProvider((_currentYear, _currentMonth)).future),
      ]);
    } catch (_) {
      // Ignorado de propósito — ver comentário acima do método.
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthEventsAsync = ref.watch(
      monthEventsProvider((_currentYear, _currentMonth)),
    );
    final upcomingEventsAsync = ref.watch(upcomingEventsProvider);
    final gmailStatusAsync = ref.watch(gmailConnectionStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendário'),
        actions: [
          IconButton(
            icon: const Icon(Icons.today_outlined),
            tooltip: 'Ir para hoje',
            onPressed: () {
              setState(() {
                final now = DateTime.now();
                _currentYear = now.year;
                _currentMonth = now.month;
              });
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const _EventFormDialog(),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        tooltip: 'Novo evento',
        child: const Icon(Icons.add),
      ),
      // `RefreshIndicator` exige um scrollable que sempre aceite o gesto de arrastar, mesmo
      // quando o conteúdo é mais curto que a viewport (mês sem eventos + "próximos eventos"
      // vazio) — sem `AlwaysScrollableScrollPhysics`, o `SingleChildScrollView` recusa a
      // overscroll nesse caso e o puxar-para-atualizar simplesmente não dispara.
      body: RefreshIndicator(
        onRefresh: _atualizar,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            12,
            12,
            12,
            80,
          ), // 80dp para evitar sobrecarga do FAB
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Conta Google cujo calendário "primary" é lido/escrito por esta tela. Discreto e sem
              // tom de desculpa, mas essencial: um evento criado no app só aparece no calendário do
              // aparelho se o app de calendário do celular estiver mostrando a MESMA conta — algo
              // indistinguível de bug para quem usa, sem essa pista.
              _CalendarAccountHint(statusAsync: gmailStatusAsync),
              // Visualização do mês com navegação
              _MonthNavigationHeader(
                ano: _currentYear,
                mes: _currentMonth,
                onPreviousMonth: () {
                  setState(() {
                    if (_currentMonth == 1) {
                      _currentYear--;
                      _currentMonth = 12;
                    } else {
                      _currentMonth--;
                    }
                  });
                },
                onNextMonth: () {
                  setState(() {
                    if (_currentMonth == 12) {
                      _currentYear++;
                      _currentMonth = 1;
                    } else {
                      _currentMonth++;
                    }
                  });
                },
              ),
              const SizedBox(height: 16),
              _MonthCalendarView(
                ano: _currentYear,
                mes: _currentMonth,
                monthEventsAsync: monthEventsAsync,
              ),
              const SizedBox(height: 24),
              // Próximos eventos usa o mesmo `_CalendarErrorPanel` da visão do mês (abaixo dizia
              // "sem painel de erro" e caía numa mensagem genérica sem ação — quem só olha esta
              // seção nunca achava o "Reconectar Gmail" que já existia lá em cima). Sim, um erro de
              // escopo simultâneo agora aparece duas vezes na tela; é uma duplicação aceitável em
              // troca de a ação corretiva estar sempre visível perto de onde a pessoa está olhando.
              Text(
                'Próximos eventos',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              upcomingEventsAsync.when(
                data: (events) {
                  if (events.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'Nenhum evento nos próximos 7 dias',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final event in events) ...[
                        _EventCard(event: event),
                        const SizedBox(height: 12),
                      ],
                    ],
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (err, __) => _CalendarErrorPanel(
                  error: err,
                  onRetry: () => ref.invalidate(upcomingEventsProvider),
                ),
              ),
              // Padding adicional na base para evitar que o FAB sobreponha o último card
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// Linha discreta indicando de qual conta Google vem o calendário "primary" lido/escrito por esta
/// tela. Some silenciosamente enquanto o status ainda carrega ou falha — não é informação crítica
/// o bastante para justificar um estado de erro próprio, e a tela já tem `_CalendarErrorPanel`
/// para as falhas que realmente importam (escopo ausente, backend indisponível).
class _CalendarAccountHint extends StatelessWidget {
  const _CalendarAccountHint({required this.statusAsync});

  final AsyncValue<GmailConnectionStatus> statusAsync;

  @override
  Widget build(BuildContext context) {
    final email = statusAsync.value?.gmailEmail;
    if (email == null || email.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        label: 'Agenda sincronizada com a conta Google $email',
        excludeSemantics: true,
        child: Row(
          children: [
            Icon(
              Icons.sync_outlined,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Sincronizado com $email',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Painel de erro exibido nos dois pontos onde a tela consome dados de calendário (próximos
/// eventos e visão do mês). Distingue três casos, em vez de tratá-los todos como um genérico
/// "erro ao carregar":
///  - [CalendarScopeException]: o usuário nunca concedeu (ou revogou) o escopo de agenda —
///    mostra uma ação de reconexão real, não só um texto passivo.
///  - [CalendarUnavailableException]: falha identificável do backend (timeout, 5xx, etc.) —
///    mostra um botão de "tentar novamente" em vez de deixar parecer que a agenda está vazia.
///  - qualquer outro erro: mensagem genérica de fallback.
class _CalendarErrorPanel extends ConsumerWidget {
  const _CalendarErrorPanel({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (error is CalendarScopeException) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Icon(
              Icons.lock_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 8),
            Text(
              'Reconecte o Gmail para usar a agenda.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _reconectarGmail(context, ref),
              child: const Text('Reconectar Gmail'),
            ),
          ],
        ),
      );
    }
    if (error is CalendarUnavailableException) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Text(
              'Não foi possível carregar a agenda agora.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: Theme.of(context).brightness == Brightness.light
                      ? _kBorderLight
                      : _kBorderDark,
                  width: 1.5,
                ),
              ),
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(
        'Erro ao carregar eventos. Verifique se o Google Calendar está conectado.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

/// Reconecta o Gmail (mesmo fluxo usado em `email_detail_screen.dart`) e força os providers de
/// calendário a recarregar, para que a tela saia do estado de erro assim que a reconexão for
/// concluída.
Future<void> _reconectarGmail(BuildContext context, WidgetRef ref) async {
  try {
    await ref.read(gmailConnectionRepositoryProvider).connect();
    ref.invalidate(gmailConnectionStatusProvider);
    ref.invalidate(upcomingEventsProvider);
    ref.invalidate(monthEventsProvider);
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Não foi possível reconectar. Tente novamente.'),
      ),
    );
  }
}

/// Cabeçalho com navegação entre meses (anterior/próximo) e mês/ano atual.
class _MonthNavigationHeader extends StatelessWidget {
  const _MonthNavigationHeader({
    required this.ano,
    required this.mes,
    required this.onPreviousMonth,
    required this.onNextMonth,
  });

  final int ano;
  final int mes;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;

  static const _meses = [
    'Janeiro',
    'Fevereiro',
    'Março',
    'Abril',
    'Maio',
    'Junho',
    'Julho',
    'Agosto',
    'Setembro',
    'Outubro',
    'Novembro',
    'Dezembro',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nomeMes = _meses[mes - 1];
    const cornerRadius = 12.0;
    final corBorda = theme.brightness == Brightness.light
        ? _kBorderLight
        : _kBorderDark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: corBorda),
        borderRadius: BorderRadius.circular(cornerRadius),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Botão anterior (48dp touch target)
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: onPreviousMonth,
              tooltip: 'Mês anterior',
            ),
          ),
          // Mês e ano centralizados
          Column(
            children: [
              Text(nomeMes, style: Theme.of(context).textTheme.titleMedium),
              Text('$ano', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          // Botão próximo (48dp touch target)
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: onNextMonth,
              tooltip: 'Próximo mês',
            ),
          ),
        ],
      ),
    );
  }
}

/// Grid visual do mês (segunda a domingo) com dias clicáveis e indicadores de eventos.
class _MonthCalendarView extends ConsumerWidget {
  const _MonthCalendarView({
    required this.ano,
    required this.mes,
    required this.monthEventsAsync,
  });

  final int ano;
  final int mes;
  final AsyncValue<List<CalendarEvent>> monthEventsAsync;

  /// Calcula quantos dias tem o mês.
  static int _diasDoMes(int ano, int mes) {
    final ultimoDia = DateTime(ano, mes + 1, 0);
    return ultimoDia.day;
  }

  /// Retorna o dia da semana (0=seg, 6=dom) para o primeiro dia do mês.
  static int _primeiroDiaDaSemana(int ano, int mes) {
    final primeiro = DateTime(ano, mes, 1);
    // DateTime.weekday: 1=segunda, 7=domingo. Convertemos para 0=segunda.
    return (primeiro.weekday - 1) % 7;
  }

  /// Retorna os eventos do dia especificado. `CalendarEvent.dataHoraInicio` já vem convertido
  /// para o fuso local em `CalendarEvent.fromJson` — sem isso, um evento perto da meia-noite
  /// podia cair no dia errado (ex.: 23h local = dia seguinte em UTC), fazendo o indicador aparecer
  /// duplicado em duas células do grid.
  List<CalendarEvent> _eventosNoDia(int dia, List<CalendarEvent> eventos) {
    return eventos.where((e) {
      final data = e.dataHoraInicio.toLocal();
      return data.year == ano && data.month == mes && data.day == dia;
    }).toList();
  }

  static const _mesesCompletos = [
    'janeiro',
    'fevereiro',
    'março',
    'abril',
    'maio',
    'junho',
    'julho',
    'agosto',
    'setembro',
    'outubro',
    'novembro',
    'dezembro',
  ];

  /// Retorna hoje (dia 1-31) se estamos no mês atual, null caso contrário.
  int? _hoje() {
    final agora = DateTime.now();
    if (agora.year == ano && agora.month == mes) {
      return agora.day;
    }
    return null;
  }

  void _abrirEventosDoDia(
    BuildContext context,
    int dia,
    List<CalendarEvent> eventosDoDia,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Eventos do dia ${dia.toString().padLeft(2, '0')}/${mes.toString().padLeft(2, '0')}',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (eventosDoDia.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Nenhum evento neste dia.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                )
              else
                ...eventosDoDia.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _EventCard(event: e),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hoje = _hoje();
    final diasTotal = _diasDoMes(ano, mes);
    final primeiroDia = _primeiroDiaDaSemana(ano, mes);
    final theme = Theme.of(context);
    final corBordaIdle = theme.brightness == Brightness.light
        ? _kBorderLight
        : _kBorderDark;
    final nomeMesCompleto = _mesesCompletos[mes - 1];

    return monthEventsAsync.when(
      data: (eventos) {
        return Column(
          children: [
            // Cabeçalho com dias da semana (altura mínima 40dp para consistência visual)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 2.0, // Mais larga que alta para cabeçalho
              ),
              itemCount: 7, // Apenas nomes dos dias
              itemBuilder: (_, index) {
                const diasSemana = [
                  'Seg',
                  'Ter',
                  'Qua',
                  'Qui',
                  'Sex',
                  'Sab',
                  'Dom',
                ];
                return Center(
                  child: Text(
                    diasSemana[index],
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            // Grid de dias do mês. `mainAxisExtent: 48` força a altura de cada linha (e,
            // portanto, de cada célula) a exatamente 48dp — o mínimo recomendado para alvo de
            // toque — independentemente da largura da tela. Sem isso, o `GridView` entrega
            // constraints apertadas (tight) para cada célula com base em `childAspectRatio`,
            // o que faz qualquer `ConstrainedBox(minHeight/minWidth: 48)` dentro dela ser inerte
            // (o `parent.enforce` de um `ConstrainedBox` sob constraints tight sempre resulta no
            // tamanho tight do pai): em telas de 320dp de largura a célula ficava com ~38.9dp de
            // altura, bem abaixo do piso de 48dp.
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                mainAxisExtent: 48,
              ),
              itemCount: 42, // 6 semanas × 7 dias
              itemBuilder: (_, index) {
                // Índices 0 a (primeiroDia-1) são células vazias
                if (index < primeiroDia) {
                  return const SizedBox.shrink();
                }

                final dia = index - primeiroDia + 1;
                if (dia > diasTotal) {
                  return const SizedBox.shrink();
                }

                final eventosDoDia = _eventosNoDia(dia, eventos);
                final temEvento = eventosDoDia.isNotEmpty;
                final ehHoje = dia == hoje;
                final qtdEventos = eventosDoDia.length;
                final rotuloEventos = qtdEventos == 0
                    ? 'nenhum evento'
                    : qtdEventos == 1
                    ? '1 evento'
                    : '$qtdEventos eventos';

                void abrirDia() =>
                    _abrirEventosDoDia(context, dia, eventosDoDia);

                return _DayCell(
                  dia: dia,
                  label: '$dia de $nomeMesCompleto, $rotuloEventos',
                  ehHoje: ehHoje,
                  temEvento: temEvento,
                  corBordaIdle: corBordaIdle,
                  onTap: abrirDia,
                );
              },
            ),
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (err, __) => _CalendarErrorPanel(
        error: err,
        onRetry: () => ref.invalidate(monthEventsProvider((ano, mes))),
      ),
    );
  }
}

/// Célula individual de dia no grid do mês. É um `StatefulWidget` (em vez de uma função que
/// devolve widgets direto no `itemBuilder`) porque o indicador de foco de teclado precisa
/// reagir a `onFocusChange` com `setState` — sem estado local não há como saber, no momento do
/// `build`, se esta célula específica está focada.
///
/// O indicador de foco usa a mesma borda opaca de 2dp em `colorScheme.primary` já usada para
/// marcar "hoje" (contraste ≈7:1 contra o scaffold claro/escuro, medido nos comentários de
/// `_kBorderLight`/`_kBorderDark` acima). Uma abordagem com cor translúcida (`focusColor` padrão
/// do `InkWell`, ou um `overlayColor` semi-transparente) foi descartada: qualquer alpha baixo o
/// bastante para não esconder o número do dia também não atinge os 3:1 mínimos exigidos para
/// indicadores de UI não-textual — só uma borda opaca resolve os dois requisitos ao mesmo tempo.
class _DayCell extends StatefulWidget {
  const _DayCell({
    required this.dia,
    required this.label,
    required this.ehHoje,
    required this.temEvento,
    required this.corBordaIdle,
    required this.onTap,
  });

  final int dia;
  final String label;
  final bool ehHoje;
  final bool temEvento;
  final Color corBordaIdle;
  final VoidCallback onTap;

  @override
  State<_DayCell> createState() => _DayCellState();
}

class _DayCellState extends State<_DayCell> {
  bool _focado = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // O anel de foco usa sempre a mesma borda opaca de 2dp em `colorScheme.primary` já usada
    // para marcar "hoje" — inclusive quando a célula É "hoje", pois o preenchimento translúcido
    // do dia atual reduz o contraste do `focusColor` padrão do `InkWell` para ~1.30:1 (abaixo do
    // piso de 3:1 exigido para indicadores de UI não-textual).
    final mostrarAnelFoco = _focado;

    return Semantics(
      button: true,
      label: widget.label,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: Container(
        // O preenchimento de fundo fica em `decoration` (não consome espaço do filho). A borda
        // fica em `foregroundDecoration`: `Container` desconta a largura de uma borda em
        // `decoration` do espaço disponível para o filho (insere o filho pela espessura da
        // borda) mas NÃO faz isso para `foregroundDecoration` — sem essa separação a borda de
        // 1-2dp reduzia a área tocável do `InkWell` para ~46.9dp, abaixo do piso de 48dp.
        decoration: BoxDecoration(
          color: widget.ehHoje
              ? colorScheme.primary.withValues(alpha: 0.25)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        foregroundDecoration: BoxDecoration(
          border: widget.ehHoje || mostrarAnelFoco
              ? Border.all(color: colorScheme.primary, width: 2)
              : Border.all(
                  color: widget.temEvento
                      ? colorScheme.secondary
                      : widget.corBordaIdle,
                  width: 1,
                ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(8),
            onFocusChange: (focado) => setState(() => _focado = focado),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.dia}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: widget.ehHoje
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: widget.ehHoje ? colorScheme.primary : null,
                    ),
                  ),
                  if (widget.temEvento)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: colorScheme.secondary,
                          shape: BoxShape.circle,
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

/// Card individual de evento com título, horário e botão de edição.
class _EventCard extends ConsumerWidget {
  const _EventCard({required this.event});

  final CalendarEvent event;

  String _formatTime(DateTime dt) {
    // `.toLocal()` de novo aqui é defensivo: `CalendarEvent.fromJson` já normaliza para local,
    // mas formatar sempre a partir do horário local (nunca UTC) é o contrato desta função,
    // independente de quem a chama no futuro.
    try {
      final local = dt.toLocal();
      final horas = local.hour.toString().padLeft(2, '0');
      final minutos = local.minute.toString().padLeft(2, '0');
      return '$horas:$minutos';
    } catch (_) {
      // Fallback defensivo se a data for malformada (ex.: ano absurdo)
      return '--:--';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final corBorda = theme.brightness == Brightness.light
        ? _kBorderLight
        : _kBorderDark;
    final horaInicio = _formatTime(event.dataHoraInicio);
    final horaFim = _formatTime(event.dataHoraFim);

    return Card(
      // O tema global usa `elevation: 0` sem sombra; sem uma borda explícita este card fica
      // indistinguível do scaffold no modo escuro (#1A1F23 sobre #1A1F23 = 1.00:1 de contraste).
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: corBorda),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Horário (secundário, pequeno)
            Text(
              '$horaInicio – $horaFim',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            // Título (principal)
            Text(
              event.titulo,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (event.descricao.isNotEmpty) ...[
              const SizedBox(height: 8),
              // Descrição (opcional, terciária)
              Text(
                event.descricao,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            // Botão de edição (altura explícita de 48dp — o mínimo recomendado de alvo de toque;
            // os 40dp anteriores ficavam abaixo disso).
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Editar'),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: corBorda, width: 1.5),
                ),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _EventFormDialog(event: event),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Formulário de criação/edição de evento (agenda sempre-editável). Em modo de criação
/// (`event == null`) chama `createEvent`; em modo de edição chama `updateEvent`. Diferente da
/// versão anterior (que mutava uma variável local `hasChanges` sem `setState`, deixando o botão
/// "Salvar" permanentemente desabilitado), este é um `ConsumerStatefulWidget` de verdade: todo
/// campo editado passa por `setState`, então o `build` sempre reflete o estado atual.
class _EventFormDialog extends ConsumerStatefulWidget {
  const _EventFormDialog({this.event});

  final CalendarEvent? event;

  @override
  ConsumerState<_EventFormDialog> createState() => _EventFormDialogState();
}

class _EventFormDialogState extends ConsumerState<_EventFormDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late DateTime _startTime;
  late DateTime _endTime;
  late bool _ehDiaInteiro;
  bool _hasChanges = false;
  bool _saving = false;

  bool get _isEditing => widget.event != null;

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    _titleController = TextEditingController(text: event?.titulo ?? '');
    _descriptionController = TextEditingController(
      text: event?.descricao ?? '',
    );
    _ehDiaInteiro = event?.ehDiaInteiro ?? false;
    if (event != null) {
      _startTime = event.dataHoraInicio;
      _endTime = event.dataHoraFim;
    } else {
      // Novo evento: sugere daqui a 1h, com 1h de duração — só um ponto de partida razoável,
      // totalmente editável através dos seletores de data/hora abaixo.
      final agora = DateTime.now();
      final sugerido = DateTime(
        agora.year,
        agora.month,
        agora.day,
        agora.hour + 1,
      );
      _startTime = sugerido;
      _endTime = sugerido.add(const Duration(hours: 1));
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _marcarAlterado() {
    if (!_hasChanges) setState(() => _hasChanges = true);
  }

  String _formatarDataHora(DateTime dt) {
    final dia = dt.day.toString().padLeft(2, '0');
    final mes = dt.month.toString().padLeft(2, '0');
    final hora = dt.hour.toString().padLeft(2, '0');
    final minuto = dt.minute.toString().padLeft(2, '0');
    return '$dia/$mes às $hora:$minuto';
  }

  Future<void> _escolherDataHora({required bool ehInicio}) async {
    final atual = ehInicio ? _startTime : _endTime;
    final data = await showDatePicker(
      context: context,
      initialDate: atual,
      firstDate: DateTime(atual.year - 1),
      lastDate: DateTime(atual.year + 5),
    );
    if (data == null || !mounted) return;
    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(atual),
    );
    if (hora == null || !mounted) return;

    setState(() {
      final novaDataHora = DateTime(
        data.year,
        data.month,
        data.day,
        hora.hour,
        hora.minute,
      );
      if (ehInicio) {
        _startTime = novaDataHora;
        if (!_endTime.isAfter(_startTime)) {
          _endTime = _startTime.add(const Duration(hours: 1));
        }
      } else {
        _endTime = novaDataHora;
      }
      _hasChanges = true;
    });
  }

  Future<void> _salvar() async {
    final titulo = _titleController.text.trim();
    if (titulo.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Dê um título ao evento.')));
      return;
    }
    if (!_endTime.isAfter(_startTime)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('O término deve ser depois do início.')),
      );
      return;
    }

    setState(() => _saving = true);
    final repo = ref.read(calendarRepositoryProvider);
    try {
      if (_isEditing) {
        await repo.updateEvent(
          eventId: widget.event!.id,
          titulo: titulo,
          descricao: _descriptionController.text.trim(),
          dataHoraInicio: _startTime,
          dataHoraFim: _endTime,
          ehDiaInteiro: _ehDiaInteiro,
        );
      } else {
        await repo.createEvent(
          titulo: titulo,
          descricao: _descriptionController.text.trim(),
          dataHoraInicio: _startTime,
          dataHoraFim: _endTime,
          ehDiaInteiro: _ehDiaInteiro,
        );
      }
      if (!mounted) return;
      // Invalida a família inteira (todas as instâncias de mês já observadas), não só o mês
      // atualmente visível — o evento pode ter mudado de mês ao ser reagendado.
      ref.invalidate(upcomingEventsProvider);
      ref.invalidate(monthEventsProvider);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditing ? 'Evento atualizado' : 'Evento criado'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditing
                ? 'Não foi possível atualizar o evento. Tente novamente.'
                : 'Não foi possível criar o evento. Tente novamente.',
          ),
        ),
      );
    }
  }

  Future<void> _excluir() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir evento?'),
        content: const Text('Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await ref.read(calendarRepositoryProvider).deleteEvent(widget.event!.id);
      if (!mounted) return;
      ref.invalidate(upcomingEventsProvider);
      ref.invalidate(monthEventsProvider);
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Evento excluído')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível excluir o evento. Tente novamente.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Editar evento' : 'Novo evento'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AppInput(
              label: 'Título',
              placeholder: 'Nome do evento',
              controller: _titleController,
              onChanged: (_) => _marcarAlterado(),
            ),
            const SizedBox(height: 16),
            AppInput(
              label: 'Descrição',
              placeholder: 'Detalhes adicionais',
              controller: _descriptionController,
              maxLines: 3,
              onChanged: (_) => _marcarAlterado(),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Início'),
              subtitle: Text(_formatarDataHora(_startTime)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _saving ? null : () => _escolherDataHora(ehInicio: true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Término'),
              subtitle: Text(_formatarDataHora(_endTime)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _saving ? null : () => _escolherDataHora(ehInicio: false),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actionsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      actions: [
        // Botão de exclusão à esquerda (se editando)
        if (_isEditing)
          TextButton(
            onPressed: _saving ? null : _excluir,
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Excluir'),
          )
        else
          const SizedBox.shrink(), // Placeholder para manter alinhamento
        // Botões de ação à direita
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: (_hasChanges || !_isEditing) && !_saving
                  ? _salvar
                  : null,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Salvar'),
            ),
          ],
        ),
      ],
    );
  }
}
