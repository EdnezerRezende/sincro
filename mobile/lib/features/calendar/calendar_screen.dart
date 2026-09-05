import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../email_triage/email_triage_providers.dart';
import 'calendar_providers.dart';
import 'calendar_event.dart';
import 'calendar_repository.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late int _currentYear;
  late int _currentMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentYear = now.year;
    _currentMonth = now.month;
  }

  @override
  Widget build(BuildContext context) {
    final monthEventsAsync = ref.watch(monthEventsProvider((_currentYear, _currentMonth)));
    final upcomingEventsAsync = ref.watch(upcomingEventsProvider);

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
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 80), // 80dp para evitar sobrecarga do FAB
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            // Próximos eventos (sem painel de erro — erros de carregamento são mostrados na
            // visão do mês, na seção principal acima; mostrar em ambos os lugares cria duplicação)
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
                    ]
                  ],
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(),
              ),
              error: (_, __) => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Erro ao carregar eventos. Verifique sua conexão.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            // Padding adicional na base para evitar que o FAB sobreponha o último card
            const SizedBox(height: 24),
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
            Icon(Icons.lock_outline, color: Theme.of(context).colorScheme.error),
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
      const SnackBar(content: Text('Não foi possível reconectar. Tente novamente.')),
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
    final nomeMes = _meses[mes - 1];
    const cornerRadius = 12.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
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
              Text(
                nomeMes,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                '$ano',
                style: Theme.of(context).textTheme.bodySmall,
              ),
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

  /// Retorna hoje (dia 1-31) se estamos no mês atual, null caso contrário.
  int? _hoje() {
    final agora = DateTime.now();
    if (agora.year == ano && agora.month == mes) {
      return agora.day;
    }
    return null;
  }

  void _abrirEventosDoDia(BuildContext context, int dia, List<CalendarEvent> eventosDoDia) {
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
    final colorScheme = Theme.of(context).colorScheme;

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
                const diasSemana = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sab', 'Dom'];
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
            // Grid de dias do mês. Garante que cada célula tenha pelo menos 48dp de altura
            // e largura (tamanho mínimo recomendado para alvo de toque). Com 7 colunas em tela
            // de 390px, isso resulta em ~48dp por célula, atendendo Material Design spec.
            // `childAspectRatio: 1.0` garante célula quadrada, e com `mainAxisSpacing: 6`
            // (em vez de 4) há espaço suficiente sem perder real-estate.
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.0,
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

                return Container(
                  decoration: BoxDecoration(
                    color: ehHoje
                        ? colorScheme.primary.withValues(alpha: 0.25)
                        : Colors.transparent,
                    border: ehHoje
                        ? Border.all(color: colorScheme.primary, width: 2)
                        : Border.all(
                      color: temEvento
                          ? colorScheme.secondary.withValues(alpha: 0.5)
                          : colorScheme.outline,
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _abrirEventosDoDia(context, dia, eventosDoDia),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$dia',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                fontWeight: ehHoje ? FontWeight.bold : FontWeight.normal,
                                color: ehHoje ? colorScheme.primary : null,
                              ),
                            ),
                            if (temEvento)
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
                );
              },
            ),
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: CircularProgressIndicator(),
      ),
      error: (err, __) => _CalendarErrorPanel(
        error: err,
        onRetry: () => ref.invalidate(monthEventsProvider((ano, mes))),
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
    final colorScheme = Theme.of(context).colorScheme;
    final horaInicio = _formatTime(event.dataHoraInicio);
    final horaFim = _formatTime(event.dataHoraFim);

    return Card(
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
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
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
    _descriptionController = TextEditingController(text: event?.descricao ?? '');
    _ehDiaInteiro = event?.ehDiaInteiro ?? false;
    if (event != null) {
      _startTime = event.dataHoraInicio;
      _endTime = event.dataHoraFim;
    } else {
      // Novo evento: sugere daqui a 1h, com 1h de duração — só um ponto de partida razoável,
      // totalmente editável através dos seletores de data/hora abaixo.
      final agora = DateTime.now();
      final sugerido = DateTime(agora.year, agora.month, agora.day, agora.hour + 1);
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
      final novaDataHora = DateTime(data.year, data.month, data.day, hora.hour, hora.minute);
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dê um título ao evento.')),
      );
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
        SnackBar(content: Text(_isEditing ? 'Evento atualizado' : 'Evento criado')),
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Evento excluído')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível excluir o evento. Tente novamente.')),
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
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Título',
                hintText: 'Nome do evento',
              ),
              onChanged: (_) => _marcarAlterado(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Descrição',
                hintText: 'Detalhes adicionais',
              ),
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
              onPressed: (_hasChanges || !_isEditing) && !_saving ? _salvar : null,
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
