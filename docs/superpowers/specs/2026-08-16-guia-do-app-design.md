# Guia rápido do app — design

## Contexto

O app não tem hoje nenhum mecanismo que explique, de forma resumida, o que
cada área faz. O onboarding existente (`mobile/lib/features/onboarding/`) é
um gate obrigatório de dados (perfil sensorial + contato de confiança),
orientado pelo backend — não é um tutorial de uso. Não existe nenhum padrão
de tutorial/coach-mark/changelog no código hoje.

Este documento descreve um guia resumido, apresentado como uma tela
dedicada, que:

1. Aparece automaticamente na primeira vez que o usuário chega na Home
   (depois do onboarding obrigatório).
2. Pode ser reaberto manualmente a qualquer momento pela tela de
   Configurações.
3. Quando uma funcionalidade nova for adicionada em uma versão futura,
   mostra automaticamente **apenas o que é novo** para quem já viu o guia
   antes — não o guia inteiro de novo.

## Escopo

Só mobile (Flutter). Nenhuma mudança de backend. Conteúdo do guia é
estático, definido em código (sem CMS/backend).

## Componentes

### `GuideItem` (modelo de conteúdo)

`mobile/lib/features/guide/guide_item.dart`

```dart
class GuideItem {
  const GuideItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.version,
  });

  final IconData icon;
  final String title;
  final String description;
  final int version;
}
```

### Lista de conteúdo (versão 1)

`mobile/lib/features/guide/guide_content.dart`

```dart
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
```

Ao adicionar uma funcionalidade nova que mereça entrar no guia: incrementar
`guiaVersaoAtual` e adicionar um `GuideItem` novo com esse número de versão.
Itens antigos nunca mudam de versão.

### `GuidePreference` (persistência local)

`mobile/lib/features/guide/guide_preference.dart` — mesmo padrão de
`BiofeedbackCache`/`HomeLayoutPreference` (`SharedPreferencesAsync`):

```dart
class GuidePreference {
  static const _chaveVersaoVista = 'guide_last_seen_version';

  final SharedPreferencesAsync _prefs;
  GuidePreference(this._prefs);

  Future<int> getVersaoVista() async {
    return await _prefs.getInt(_chaveVersaoVista) ?? 0;
  }

  Future<void> setVersaoVista(int versao) {
    return _prefs.setInt(_chaveVersaoVista, versao);
  }
}
```

Exposto via um provider Riverpod (`guidePreferenceProvider`), seguindo o
padrão dos demais providers de preferências locais no projeto.

### Filtro de itens a mostrar

Uma função pura, testável isoladamente:

```dart
List<GuideItem> itemsToShow(List<GuideItem> items, int versaoVista) {
  return items.where((item) => item.version > versaoVista).toList();
}
```

Com `versaoVista = 0` (primeira vez), retorna todos os itens — não há
tratamento especial para "guia completo" vs. "novidades": é a mesma função
nos dois casos, e o único parâmetro que muda é `versaoVista`.

### `GuideScreen` (UI)

`mobile/lib/features/guide/guide_screen.dart`

```dart
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key, required this.items, required this.title});

  final List<GuideItem> items;
  final String title;
  // ...
}
```

- `ListView` simples: `icon` + `title` + `description` (1 linha) por item,
  usando `Theme.of(context)` / `context.sincroColors` — sem cores fixas.
- Botão "Entendi" no rodapé fecha a tela e persiste
  `guidePreference.setVersaoVista(guiaVersaoAtual)`.
- Não é uma rota nomeada em `main.dart` — como `EmailDetailScreen` e outras
  telas parametrizadas do projeto, é aberta via
  `Navigator.push(MaterialPageRoute(builder: (_) => GuideScreen(...)))`.
- `title` é decidido por quem abre a tela: `'Guia rápido do Sincro'` para a
  lista completa, `'Novidades'` para uma lista filtrada por versão.

## Pontos de entrada

### 1. Automático — `HomeScreen`

Mesmo padrão já usado para `_registerFcmToken` (chamada em
`addPostFrameCallback` no `initState`):

```dart
Future<void> _checkGuide() async {
  final versaoVista = await ref.read(guidePreferenceProvider).getVersaoVista();
  final pendentes = itemsToShow(guideItems, versaoVista);
  if (pendentes.isEmpty || !mounted) return;
  await Navigator.push(context, MaterialPageRoute(
    builder: (_) => GuideScreen(
      items: pendentes,
      title: versaoVista == 0 ? 'Guia rápido do Sincro' : 'Novidades',
    ),
  ));
}
```

Chamada junto com `_registerFcmToken()` no mesmo `addPostFrameCallback`.

### 2. Manual — `SettingsScreen`

Novo `ListTile` (nova seção "Ajuda", ou dentro de "Perfil & Preferências" —
a implementação decide o encaixe visual seguindo o padrão de seções
existente):

```dart
ListTile(
  leading: const Icon(Icons.help_outline),
  title: const Text('Ver guia do app'),
  onTap: _busy ? null : () => Navigator.push(context, MaterialPageRoute(
    builder: (_) => const GuideScreen(items: guideItems, title: 'Guia rápido do Sincro'),
  )),
),
```

Reabrir pelo menu **sempre mostra a lista completa**, ignorando
`versaoVista` — reabrir pelo menu significa "quero ver o guia inteiro de
novo", não "quero ver só as novidades". Ao fechar essa tela, o `versaoVista`
salvo também é atualizado para `guiaVersaoAtual` (idempotente — já deve
estar nesse valor na maioria dos casos).

## Erros e casos de borda

- `SharedPreferencesAsync` falhando na leitura: `getVersaoVista()` já tem
  fallback `?? 0` — pior caso, o guia aparece de novo uma vez a mais, o que
  é aceitável (não há caminho de erro visível ao usuário).
- Sem itens pendentes (`itemsToShow` vazio): a Home simplesmente não
  navega — nenhum efeito visual.
- Botão "Entendi" falhando ao persistir (ex.: storage indisponível): a tela
  fecha normalmente; o guia pode reaparecer na próxima abertura da Home —
  aceitável, mesmo raciocínio do item acima.

## Testes

- `guide_preference_test.dart`: get/set de `versaoVista`, incluindo o
  fallback para `0` quando nunca foi salvo.
- `guide_content_test.dart` (ou junto do preference test):
  `itemsToShow` — retorna tudo quando `versaoVista == 0`; retorna só itens
  com `version > versaoVista`; retorna vazio quando `versaoVista >=` maior
  versão existente.
- Sem teste `pumpWidget` para `GuideScreen` — verificação manual, seguindo
  a convenção já estabelecida neste projeto para telas.

## Fora de escopo (YAGNI)

- `package_info_plus` / versionamento real de app — decidido explicitamente
  contra isso; usa constante manual `guiaVersaoAtual`, mesmo padrão de
  `BiofeedbackCache.versaoPermissoesAtual`.
- Indicador visual de "novo" (badge) dentro da lista — a tela de novidades
  já mostra só os itens novos, não precisa destacar dentro de uma lista
  maior.
- Analytics/telemetria de quantos usuários veem o guia.
- Internacionalização — conteúdo só em português, como o resto do app.
