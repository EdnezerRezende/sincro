import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'anamnese_answers.dart';
import 'anamnese_providers.dart';

const _gatilhosDisponiveis = [
  'Abrir o app do banco',
  'Ligações não agendadas',
  'Mudança de última hora na agenda',
  'Ambientes barulhentos',
];

class AnamneseWizardScreen extends ConsumerStatefulWidget {
  const AnamneseWizardScreen({super.key, this.isEditing = false});

  /// When true, this screen is being reused post-onboarding to edit an
  /// existing sensory profile, so submitting should simply return to the
  /// caller instead of continuing the onboarding flow.
  final bool isEditing;

  @override
  ConsumerState<AnamneseWizardScreen> createState() => _AnamneseWizardScreenState();
}

class _AnamneseWizardScreenState extends ConsumerState<AnamneseWizardScreen> {
  final _pageController = PageController();
  int _step = 0;
  bool _submitting = false;
  bool _loadingExisting = false;

  @override
  void initState() {
    super.initState();
    if (widget.isEditing) {
      _loadingExisting = true;
      // Seed the wizard from the previously saved profile so editing
      // doesn't start from a blank slate (which would silently discard
      // unedited fields when the user confirms).
      Future.microtask(() async {
        try {
          await ref.read(anamneseNotifierProvider.notifier).loadExisting();
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Não foi possível carregar seu perfil salvo. Você pode preenchê-lo novamente.')),
            );
          }
        } finally {
          if (mounted) setState(() => _loadingExisting = false);
        }
      });
    }
  }

  void _goToStep(int step) {
    setState(() => _step = step);
    _pageController.animateToPage(step, duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    setState(() => _submitting = true);
    try {
      await ref.read(anamneseNotifierProvider.notifier).submit();
      if (!mounted) return;
      if (widget.isEditing) {
        Navigator.of(context).pop(true);
      } else {
        Navigator.of(context).pushReplacementNamed('/onboarding/contacts');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível salvar seu perfil. Tente novamente.')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final answers = ref.watch(anamneseNotifierProvider);
    final notifier = ref.read(anamneseNotifierProvider.notifier);

    if (_loadingExisting) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: Text('Sobre você (${_step + 1}/4)')),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _NotificationStep(
            selected: answers.toleranciaNotificacao,
            onSelect: (value) {
              notifier.setTolerancia(value);
              _goToStep(1);
            },
          ),
          _TriggersStep(
            selected: answers.gatilhos,
            outroGatilho: answers.outroGatilho,
            onToggle: notifier.toggleGatilho,
            onSetOutroGatilho: notifier.setOutroGatilho,
            onNext: () => _goToStep(2),
          ),
          _ToneStep(
            selected: answers.tomPreferido,
            onSelect: (value) {
              notifier.setTom(value);
              _goToStep(3);
            },
          ),
          _SummaryStep(
            answers: answers,
            onEditStep: _goToStep,
            onConfirm: _submitting ? null : _finish,
          ),
        ],
      ),
    );
  }
}

class _NotificationStep extends StatelessWidget {
  const _NotificationStep({required this.selected, required this.onSelect});

  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: 'Como você prefere receber notificações?',
      children: [
        _ChoiceButton(label: 'Silenciosas', value: 'SILENCIOSAS', groupValue: selected, onSelect: onSelect),
        _ChoiceButton(label: 'Só em horários específicos', value: 'HORARIOS_ESPECIFICOS', groupValue: selected, onSelect: onSelect),
        _ChoiceButton(label: 'Padrão', value: 'PADRAO', groupValue: selected, onSelect: onSelect),
      ],
    );
  }
}

class _TriggersStep extends StatefulWidget {
  const _TriggersStep({
    required this.selected,
    required this.outroGatilho,
    required this.onToggle,
    required this.onSetOutroGatilho,
    required this.onNext,
  });

  final List<String> selected;
  final String? outroGatilho;
  final ValueChanged<String> onToggle;
  final ValueChanged<String?> onSetOutroGatilho;
  final VoidCallback onNext;

  @override
  State<_TriggersStep> createState() => _TriggersStepState();
}

class _TriggersStepState extends State<_TriggersStep> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.outroGatilho ?? '');
  }

  @override
  void didUpdateWidget(_TriggersStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only update controller text if the external value changed
    // (avoid overwriting if user is actively typing)
    if (oldWidget.outroGatilho != widget.outroGatilho && widget.outroGatilho != null) {
      _controller.text = widget.outroGatilho!;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: 'Algum desses costuma te incomodar?',
      children: [
        Wrap(
          spacing: 8,
          children: _gatilhosDisponiveis.map((gatilho) {
            return FilterChip(
              label: Text(gatilho),
              selected: widget.selected.contains(gatilho),
              onSelected: (_) => widget.onToggle(gatilho),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        TextField(
          onChanged: widget.onSetOutroGatilho,
          controller: _controller,
          decoration: InputDecoration(
            hintText: 'Outro gatilho (opcional)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(onPressed: widget.onNext, child: const Text('Continuar')),
      ],
    );
  }
}

class _ToneStep extends StatelessWidget {
  const _ToneStep({required this.selected, required this.onSelect});

  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: 'Como você prefere que as mensagens sejam escritas?',
      children: [
        _ChoiceButton(label: 'Direto e curto', value: 'DIRETO_E_CURTO', groupValue: selected, onSelect: onSelect),
        _ChoiceButton(label: 'Levemente mais explicativo', value: 'EXPLICATIVO', groupValue: selected, onSelect: onSelect),
      ],
    );
  }
}

class _SummaryStep extends StatelessWidget {
  const _SummaryStep({required this.answers, required this.onEditStep, required this.onConfirm});

  final AnamneseAnswers answers;
  final ValueChanged<int> onEditStep;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: 'Confirme suas respostas',
      children: [
        ListTile(
          title: const Text('Notificações'),
          subtitle: Text(answers.toleranciaNotificacao ?? '—'),
          trailing: TextButton(onPressed: () => onEditStep(0), child: const Text('Editar')),
        ),
        ListTile(
          title: const Text('Gatilhos'),
          subtitle: Text(
            [
              if (answers.gatilhos.isNotEmpty) answers.gatilhos.join(', '),
              if (answers.outroGatilho?.isNotEmpty ?? false) answers.outroGatilho,
            ].join(' + ').isEmpty
                ? 'Nenhum'
                : [
                    if (answers.gatilhos.isNotEmpty) answers.gatilhos.join(', '),
                    if (answers.outroGatilho?.isNotEmpty ?? false) answers.outroGatilho,
                  ].join(' + '),
          ),
          trailing: TextButton(onPressed: () => onEditStep(1), child: const Text('Editar')),
        ),
        ListTile(
          title: const Text('Tom preferido'),
          subtitle: Text(answers.tomPreferido ?? '—'),
          trailing: TextButton(onPressed: () => onEditStep(2), child: const Text('Editar')),
        ),
        const SizedBox(height: 24),
        ElevatedButton(onPressed: onConfirm, child: const Text('Confirmar')),
      ],
    );
  }
}

class _StepScaffold extends StatelessWidget {
  const _StepScaffold({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 24),
          ...children,
        ],
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onSelect,
  });

  final String label;
  final String value;
  final String? groupValue;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final isSelected = groupValue == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
        ),
        onPressed: () => onSelect(value),
        child: Text(label),
      ),
    );
  }
}
