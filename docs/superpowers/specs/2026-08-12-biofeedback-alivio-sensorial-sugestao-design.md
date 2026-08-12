# Sincro — Biofeedback & Alívio Sensorial: Sugestão de Card no Alerta

## Contexto

O pilar Biofeedback & Crise tem 3 fases implementadas e mescladas em `master`:
Fase 1 (`docs/superpowers/specs/2026-08-03-biofeedback-conexao-smartwatch-design.md`) conecta o
smartwatch e mostra FC/VFC; Fase 2
(`docs/superpowers/specs/2026-08-04-biofeedback-deteccao-estresse-design.md`) detecta o estado
"Calmo"/"Elevado"/"Coletando dados"; Fase 3
(`docs/superpowers/specs/2026-08-04-biofeedback-alertas-descompressao-design.md`) dispara uma
notificação local calma quando o estado transiciona para "Elevado", com o texto explícito: *"a
técnica de alívio em si (respiração guiada, grounding) fica para o pilar Comunidade & Alívio
Sensorial — esta fase só cobre a detecção-para-alerta, não a intervenção."*

O pilar Comunidade & Alívio Sensorial, por sua vez
(`docs/superpowers/specs/2026-08-06-alivio-sensorial-grounding-cards-design.md`), entregou a
biblioteca de grounding cards (favoritar, filtrar por categoria, tela de detalhe com passo a
passo), mas deixou explicitamente fora de escopo a *"sugestão contextual a partir do Biofeedback
... fica para uma fase futura"*.

Ou seja: os dois pilares existem e funcionam de forma independente, mas o loop que o documento de
pesquisa original (`docs/App para Autistas_ Finanças e Bem-Estar.pdf`) sempre previu — o alerta de
estresse abrindo direto uma técnica de descompressão (*"Modo Descompressão: Exercícios de
respiração / aterramento (grounding)"*) — nunca foi conectado. Este documento fecha esse loop.

## Objetivo desta fase

Ao final desta fase, quando o `BiofeedbackStressDetector` detecta a transição para `elevado` e o
alerta de descompressão (Fase 3) dispara:

1. A notificação local sugere um grounding card específico pelo nome, em vez do texto genérico
   atual.
2. Tocar a notificação abre diretamente a tela de detalhe daquele card — não mais a tela de
   detalhe do Biofeedback.
3. Se não for possível escolher um card (diretório vazio ou falha de rede no momento do alerta), a
   notificação continua disparando com o comportamento de hoje (texto genérico, toque abre
   `/biofeedback`) — a ausência de sugestão nunca cancela o alerta em si.

## Fora de escopo

- **Qualquer sugestão passiva na tela `/biofeedback`.** Esta fase cobre só o caminho da
  notificação; a tela de detalhe do Biofeedback não ganha nenhum elemento novo.
- **Novo endpoint de backend.** A escolha do card usa exclusivamente os endpoints já existentes
  (`GET /grounding-cards`, `GET /grounding-cards?categoria=`, `GET /grounding-cards/favoritos`) —
  nenhuma mudança em `backend/src/grounding-cards/`.
- **Enviar qualquer dado de FC/VFC/estresse ao backend.** A escolha do card acontece inteiramente
  no dispositivo (mobile), lendo o diretório público de cards — não é diferente, em termos de
  privacidade, da leitura de `toleranciaNotificacao` que a Fase 3 já faz. Nenhum dado de saúde
  passa a trafegar pela rede nesta fase.
- **Aprendizado/personalização ao longo do tempo** (ex.: parar de sugerir um card que o usuário
  sempre ignora, ou aprender qual categoria funciona melhor para cada pessoa). A ordem de
  prioridade desta fase é fixa (favoritos → Respiração → qualquer card ativo).
- **Alterar o texto do título da notificação** (`"Um momento para respirar"`) — só o corpo muda.
- **Mudar a lógica de `deveAlertar`** (quando notificar) — esta fase só muda o que a notificação
  diz e para onde o toque leva, não quando ela dispara.

## Arquitetura

### Escolha do card sugerido

Nova função pura em `mobile/lib/features/biofeedback/`, sem I/O — recebe as listas já buscadas e
devolve uma escolha, mesmo padrão de `BiofeedbackStressDetector`/`deveAlertar`:

```dart
String? escolherCardSugerido({
  required List<GroundingCard> favoritos,
  required List<GroundingCard> respiracaoAtivos,
  required List<GroundingCard> todosAtivos,
  required int Function(int max) sortear, // devolve um índice em [0, max) — mesmo contrato de Random.nextInt; injetado para testes determinísticos
}) {
  if (favoritos.isNotEmpty) return favoritos[sortear(favoritos.length)].id;
  if (respiracaoAtivos.isNotEmpty) return respiracaoAtivos[sortear(respiracaoAtivos.length)].id;
  if (todosAtivos.isNotEmpty) return todosAtivos[sortear(todosAtivos.length)].id;
  return null;
}
```

`BiofeedbackSyncService._notificarSeNecessario` (já existe) passa a, **só depois** que
`deveAlertar` já retornou `true` (mesma otimização já documentada no código: não gastar chamada de
rede em ciclos sem transição relevante), buscar as três listas via `GroundingCardsRepository` (já
existe, reaproveitado sem mudança) e chamar `escolherCardSugerido`. Cada uma das três buscas é
best-effort: uma falha em qualquer uma delas é tratada como lista vazia, cai para a próxima
prioridade, e se todas falharem o resultado é `null` — nunca uma exceção que impediria o alerta em
si de disparar (mesma postura de todo o resto da sincronização em background, ex.:
`_garantirPermissoesAtualizadas`).

`GroundingCardsRepository` já é usado hoje só no isolate principal (via Riverpod); esta fase
instancia um `GroundingCardsRepository(dio)` diretamente dentro de
`biofeedbackCallbackDispatcher` (mesmo padrão já usado ali para `SensoryProfileRepository`), com o
mesmo `Dio` autenticado (ou o fallback sem token, se `Firebase.initializeApp()` falhar no isolate —
nesse caso as buscas falham com 401 e caem no mesmo tratamento best-effort acima).

### Notificação

`BiofeedbackAlertService.mostrarAlerta` ganha um parâmetro opcional:

```dart
Future<void> mostrarAlerta({GroundingCard? cardSugerido}) async {
  final corpo = cardSugerido != null
      ? 'Que tal experimentar ${cardSugerido.titulo} agora?'
      : _corpoAlerta; // constante já existente, texto inalterado
  final payload = cardSugerido != null
      ? '$biofeedbackNotificationTapPayload:${cardSugerido.id}'
      : biofeedbackNotificationTapPayload;
  // título continua fixo: "Um momento para respirar"
  ...
}
```

O payload continua uma string simples (consistente com o mecanismo já usado pelo
`flutter_local_notifications` neste app) — um `:` seguido do id do card quando há sugestão, ausente
quando não há. `biofeedbackNotificationTapPayload` (a constante `'biofeedback_alerta'`) continua
sendo o prefixo usado para reconhecer o tipo de notificação, agora verificado com
`startsWith` em vez de igualdade exata.

### Navegação ao tocar

`_handleBiofeedbackAlertTap` roda no isolate principal (não no isolate de background do
`workmanager`), então continua com acesso normal ao `ProviderScope` já montado por `runApp` — não
precisa (e não deve) instanciar `Dio`/repositório manualmente como o isolate de background faz;
isso é exclusivo de lá, onde não existe árvore de widgets.

1. Verificar `response.payload?.startsWith(biofeedbackNotificationTapPayload) ?? false` (era
   `== ` antes).
2. Extrair o id após o primeiro `:`, se houver (o prefixo em si nunca contém `:`, e ids são UUIDs,
   então não há ambiguidade no split).
3. Sem id → `navigatorKey.currentState?.pushNamed('/biofeedback')` (comportamento atual, inalterado).
4. Com id → `navigatorKey.currentState?.pushNamed('/grounding-cards/sugerido', arguments: cardId)`.
   `'/grounding-cards/sugerido'` é uma rota nova no `routes:` table de `main.dart`, registrada como
   `(_) => const GroundingCardSugeridoScreen()` (mesmo padrão estático já usado por toda rota deste
   app — nenhuma mudança para `onGenerateRoute`); a nova tela lê o id via
   `ModalRoute.of(context)!.settings.arguments as String` no `build()`. Ela é um
   `ConsumerWidget` que usa o `groundingCardsProvider(null)` já existente (lista de cards ativos,
   mesmo provider que a biblioteca usa). A localização do card pelo id é uma função pura própria,
   `GroundingCard? resolverCardSugerido({required List<GroundingCard> cards, required String id})`
   (mesmo espírito de `escolherCardSugerido` — lógica extraída e testável sem depender do widget):
   - Encontrado → `GroundingCardDetailScreen(card: card, favoritadoInicial: ...)` (o
     `favoritadoInicial` vem de `groundingCardFavoritosProvider`, mesmo padrão já usado pela
     biblioteca ao abrir um card).
   - Carregando → um `CircularProgressIndicator` simples (a busca é rápida, diretório pequeno).
   - Não encontrado (`resolverCardSugerido` devolve `null`) ou erro de rede → navega para
     `/biofeedback` como fallback, sem tela quebrada.
5. Mesmo guard de sessão já existente (`FirebaseAuth.instance.currentUser == null` → não navega)
   se aplica igualmente a este novo caminho, verificado antes do passo 1.

## Modelo de dados e UI

Nenhuma migration, nenhuma mudança de schema. Um único widget novo, pequeno e sem UI própria
visível (`GroundingCardSugeridoScreen`, descrito acima) — ele só resolve o id recebido e
redireciona para a tela de detalhe já existente (`GroundingCardDetailScreen`) ou para
`/biofeedback`; não é uma tela de destino em si, é o elo entre a notificação e o destino.

## Segurança e Privacidade

- Nenhum dado de FC/VFC/passos/treino/estado de estresse passa a trafegar pela rede nesta fase — a
  escolha do card lê só o diretório público de grounding cards (já lido hoje pela tela da
  biblioteca) e, quando há favoritos, a lista de favoritos do próprio usuário autenticado (já lida
  hoje pela mesma tela) — nenhum dado novo, nenhum destino novo.
- O corpo da notificação passa a conter o título de um grounding card (ex.: "Respiração 4-7-8") —
  não é dado de saúde sensível (é conteúdo público/curado pela equipe Sincro, o mesmo texto visível
  na biblioteca), então continua dentro do mesmo nível de exposição já aceito para as notificações
  deste app na tela de bloqueio/central de notificações do sistema.

## Testes

- **`escolherCardSugerido`** (função pura, nova): favoritos não-vazio → escolhe entre favoritos,
  ignorando as outras duas listas; favoritos vazio + Respiração não-vazio → escolhe entre
  Respiração; favoritos e Respiração vazios + todosAtivos não-vazio → escolhe entre todosAtivos;
  as três vazias → `null`; a função `sortear` injetada permite fixar qual índice "sorteado" cada
  teste espera, tornando os testes determinísticos.
- **`BiofeedbackAlertService.mostrarAlerta`**: com `cardSugerido` → corpo menciona o título, payload
  termina em `:<id>`; sem `cardSugerido` → corpo e payload idênticos ao comportamento já testado
  hoje.
- **Extração do id do payload**: isolada numa função pura própria (ex.:
  `String? extrairCardIdDoPayload(String? payload)`), testável sem tocar `Navigator`/
  `FirebaseAuth` — payload nulo, payload igual ao prefixo (sem `:`), payload com `:<id>` → cada
  caso devolvendo o id certo ou `null`. O restante de `_handleBiofeedbackAlertTap` (guard de
  sessão, chamadas a `pushNamed`) depende de globais (`navigatorKey`, `FirebaseAuth.instance`) e
  segue a mesma situação já registrada na spec da Fase 3: não automatizado em `flutter test`,
  coberto por verificação manual (ver abaixo) — este documento não muda esse precedente, só
  estende a mesma lógica com mais um caminho de navegação possível.
- **`resolverCardSugerido`** (função pura, nova): id presente na lista → devolve o card certo; id
  ausente → devolve `null`; lista vazia → devolve `null`. `GroundingCardSugeridoScreen` em si não
  ganha teste de widget (`pumpWidget`) — mesma convenção já estabelecida e documentada na spec de
  Conexão Profissional e reafirmada na de Alívio Sensorial ("nenhuma tela ganha teste de widget...
  a UI é coberta por verificação manual"); este documento não muda essa convenção.
- **`BiofeedbackSyncService._notificarSeNecessario`**: falha em uma ou mais das três buscas de
  grounding cards não impede `_alertService.mostrarAlerta()` de ser chamado — só chega sem
  `cardSugerido`.
- **Verificação manual** (mesma ressalva das fases anteriores deste pilar): disparo real da
  notificação com o corpo mencionando o card, toque abrindo o card correto com o app em cada um dos
  três estados (fechado, em background, aberto), e o fallback funcionando de fato quando o
  diretório de cards está vazio.
