import 'package:flutter/material.dart';

/// Tela de fechamento suave, mostrada quando a pessoa encerra um jogo de
/// regulação sensorial (Voo Sereno, Estrada Tranquila).
///
/// Sem placar, sem avaliação de desempenho: apenas quanto tempo a pessoa
/// ficou ali e uma pergunta gentil sobre como ela está agora. As três opções
/// só mostram uma resposta curta e acolhedora — nada é enviado a lugar
/// nenhum, não há `backend` nem persistência aqui.
///
/// Widget genérico e autocontido (não depende de nenhum jogo específico) —
/// pensado para ser reaproveitado por qualquer tela de jogo calmante.
class CalmingSessionSummary extends StatelessWidget {
  const CalmingSessionSummary({
    super.key,
    required this.elapsed,
    required this.onContinue,
    required this.onExit,
    this.gameName,
  });

  /// Tempo total que a pessoa passou na sessão.
  final Duration elapsed;

  /// Chamado ao tocar em "Continuar": volta ao jogo de onde parou.
  final VoidCallback onContinue;

  /// Chamado ao tocar em "Sair": encerra de fato e deixa a tela do jogo.
  final VoidCallback onExit;

  /// Nome do jogo (ex.: "Voo Sereno"), mostrado como um rótulo discreto
  /// acima da mensagem principal. Opcional.
  final String? gameName;

  /// Texto "Você ficou N min aqui", com pluralização e o caso especial de
  /// menos de um minuto.
  @visibleForTesting
  static String timeSpentLabel(Duration elapsed) {
    if (elapsed < const Duration(minutes: 1)) {
      return 'Você ficou menos de um minuto aqui.';
    }
    final int minutes = elapsed.inMinutes;
    final String unit = minutes == 1 ? 'minuto' : 'minutos';
    return 'Você ficou $minutes $unit aqui.';
  }

  @override
  Widget build(BuildContext context) {
    return _CalmingSessionSummaryBody(
      elapsed: elapsed,
      onContinue: onContinue,
      onExit: onExit,
      gameName: gameName,
    );
  }
}

enum _HowFeeling { calmer, same, restless }

class _CalmingSessionSummaryBody extends StatefulWidget {
  const _CalmingSessionSummaryBody({
    required this.elapsed,
    required this.onContinue,
    required this.onExit,
    required this.gameName,
  });

  final Duration elapsed;
  final VoidCallback onContinue;
  final VoidCallback onExit;
  final String? gameName;

  @override
  State<_CalmingSessionSummaryBody> createState() => _CalmingSessionSummaryBodyState();
}

class _CalmingSessionSummaryBodyState extends State<_CalmingSessionSummaryBody> {
  _HowFeeling? _selected;

  String get _response {
    switch (_selected!) {
      case _HowFeeling.calmer:
        return 'Que bom. Volte quando quiser.';
      case _HowFeeling.same:
        return 'Tudo bem. Fique mais um pouco se quiser.';
      case _HowFeeling.restless:
        return 'Tudo bem. Respirar devagar já ajuda. Quer tentar mais um pouco?';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Material(
      color: scheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Spacer(),
              if (widget.gameName != null) ...<Widget>[
                Text(
                  widget.gameName!,
                  textAlign: TextAlign.center,
                  style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                CalmingSessionSummary.timeSpentLabel(widget.elapsed),
                textAlign: TextAlign.center,
                style: text.headlineSmall?.copyWith(color: scheme.onSurface),
              ),
              const SizedBox(height: 32),
              Text(
                'Como está agora?',
                textAlign: TextAlign.center,
                style: text.bodyLarge?.copyWith(color: scheme.onSurface),
              ),
              const SizedBox(height: 16),
              _FeelingChip(
                label: 'Mais calmo(a)',
                selected: _selected == _HowFeeling.calmer,
                onTap: () => setState(() => _selected = _HowFeeling.calmer),
              ),
              const SizedBox(height: 12),
              _FeelingChip(
                label: 'Igual',
                selected: _selected == _HowFeeling.same,
                onTap: () => setState(() => _selected = _HowFeeling.same),
              ),
              const SizedBox(height: 12),
              _FeelingChip(
                label: 'Ainda agitado(a)',
                selected: _selected == _HowFeeling.restless,
                onTap: () => setState(() => _selected = _HowFeeling.restless),
              ),
              const SizedBox(height: 20),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _selected == null
                    ? const SizedBox(height: 24)
                    : Padding(
                        key: ValueKey<_HowFeeling>(_selected!),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          _response,
                          textAlign: TextAlign.center,
                          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
              ),
              const Spacer(),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: widget.onContinue,
                  child: const Text('Continuar'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: widget.onExit,
                  child: const Text('Sair'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chip grande e tocável (>= 48 dp de altura), estilo "escolha", sem
/// depender de `ChoiceChip` do Material para garantir a altura mínima e o
/// visual suave pedido para este contexto.
class _FeelingChip extends StatelessWidget {
  const _FeelingChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? scheme.primary : scheme.outline),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? scheme.onPrimary : scheme.onSurface,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
