/// Preferência de layout da tela inicial. Neurodivergências variam: algumas pessoas preferem o
/// mínimo de informação por vez, outras preferem mais informação organizada — o Sincro deixa a
/// escolha com o usuário, trocável a qualquer momento em Configurações.
enum HomeLayoutMode {
  /// Um único scroll com todos os cards empilhados — o comportamento original do app, com o
  /// menor volume de informação simultânea na tela.
  resumo('Resumo simples'),

  /// Abas Hoje / Finanças / Apoio — mais informação organizada por contexto, para quem prefere
  /// navegar entre seções em vez de rolar uma lista longa.
  abas('Abas (Hoje / Finanças / Apoio)');

  const HomeLayoutMode(this.label);

  final String label;
}
