import 'package:flutter/material.dart';
import 'guide_item.dart';

const guiaVersaoAtual = 1;

const guideItems = <GuideItem>[
  GuideItem(
    icon: Icons.home_outlined,
    title: 'Home',
    description: 'Veja um resumo do seu dia, ou troque para abas (Hoje, '
        'Finanças, Apoio) nas Configurações.',
    version: 1,
  ),
  GuideItem(
    icon: Icons.account_balance_wallet_outlined,
    title: 'Finanças',
    description: 'Acompanhe seus gastos e receitas conectando suas contas.',
    version: 1,
  ),
  GuideItem(
    icon: Icons.favorite_outline,
    title: 'Biofeedback',
    description: 'O app usa dados do seu smartwatch para identificar sinais '
        'de estresse e sugerir uma pausa.',
    version: 1,
  ),
  GuideItem(
    icon: Icons.mail_outline,
    title: 'E-mails',
    description: 'Receba rascunhos de resposta prontos para e-mails que '
        'chegam na sua caixa.',
    version: 1,
  ),
  GuideItem(
    icon: Icons.people_outline,
    title: 'Contatos de confiança',
    description: 'Pessoas que podem ser acionadas em um momento de crise.',
    version: 1,
  ),
  GuideItem(
    icon: Icons.medical_services_outlined,
    title: 'Profissionais',
    description: 'Encontre profissionais de apoio perto de você.',
    version: 1,
  ),
  GuideItem(
    icon: Icons.spa_outlined,
    title: 'Cartões de acalma-se',
    description: 'Técnicas rápidas de grounding para momentos difíceis.',
    version: 1,
  ),
  GuideItem(
    icon: Icons.sos_outlined,
    title: 'Emergência',
    description: 'Botão de emergência para pedir ajuda rapidamente.',
    version: 1,
  ),
];

/// Mesma função filtra a lista completa (primeira vez, `versaoVista == 0`) e as novidades de uma
/// atualização (`versaoVista > 0`) — não há caminho especial para "guia completo".
List<GuideItem> itemsToShow(List<GuideItem> items, int versaoVista) {
  return items.where((item) => item.version > versaoVista).toList();
}
