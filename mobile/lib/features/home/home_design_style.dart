/// Preferência de estilo visual da tela inicial.
/// Neurodivergências variam: algumas pessoas preferem minimalismo, outras preferem visual mais rico.
enum HomeDesignStyle {
  /// Máximo espaço negativo, elegância refinada — para quem gosta de respiro visual.
  minimalista('Minimalista Refinado'),

  /// Visual contemporâneo com ícones e gradientes sutis — moderno mas acessível.
  moderno('Moderno Suave'),

  /// Máxima clareza visual, layout tipo lista — para quem prefere tudo visível.
  funcional('Funcional Direto');

  const HomeDesignStyle(this.label);

  final String label;
}
