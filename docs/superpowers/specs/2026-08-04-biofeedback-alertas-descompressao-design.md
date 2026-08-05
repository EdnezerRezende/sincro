# Sincro — Biofeedback & Crise: Alertas de Descompressão (Fase 3 deste pilar)

## Contexto

A Fase 1 deste pilar (`docs/superpowers/specs/2026-08-03-biofeedback-conexao-smartwatch-design.md`)
deu ao usuário a leitura de FC/VFC do smartwatch, 100% on-device. A Fase 2
(`docs/superpowers/specs/2026-08-04-biofeedback-deteccao-estresse-design.md`) adicionou a
detecção de estresse: um `BiofeedbackStressDetector` que compara a FC/VFC de repouso do dia
contra uma linha de base pessoal e produz um estado `calmo` / `elevado` / `coletandoDados`,
mostrado passivamente na Home e na tela de detalhe — sem nenhum alerta, sem nenhuma notificação.
Ambas as fases estão implementadas e mescladas em `master`.

Esta fase (Fase 3) fecha o ciclo que o spec original do pilar (`docs/superpowers/specs/2026-08-01-onboarding-anamnese-rede-apoio-design.md`)
chamava de "alertas de descompressão": quando o estado passa a `elevado`, o app avisa o usuário
através de uma notificação local calma. A técnica de alívio em si (respiração guiada, grounding)
fica para o pilar "Comunidade & Alívio Sensorial" (ainda sem spec) — esta fase só cobre a
detecção-para-alerta, não a intervenção.

## Objetivo desta fase

Ao final desta fase, o usuário deve poder:

1. Receber uma notificação local do dispositivo, com texto calmo (sem tom de urgência/alarme),
   quando o `BiofeedbackStressDetector` detecta a **transição** de um estado não-elevado
   (`calmo` ou `coletandoDados`) para `elevado` — inclusive quando isso acontece durante a
   sincronização em background, com o app fechado.
2. Tocar a notificação e ser levado direto para a tela de detalhe do Biofeedback (`/biofeedback`).
3. Desativar só esses alertas, em Configurações, sem precisar desativar o Biofeedback inteiro
   (que continua mostrando o estado normalmente, só para de notificar).
4. Ter os alertas respeitando a mesma preferência de tolerância de notificação (`toleranciaNotificacao`)
   que já governa as notificações de Gmail e Finanças — sem essa preferência ser `'PADRAO'`,
   nenhum alerta é disparado.

## Fora de escopo

- Qualquer técnica de descompressão/alívio embutida no app (respiração guiada, grounding, etc.) —
  fica para o pilar "Comunidade & Alívio Sensorial".
- Alertar para os estados `calmo` ou `coletandoDados` — só a transição para `elevado` gera
  notificação.
- Cooldown/limite de tempo mínimo entre alertas além da própria lógica de transição — se o estado
  oscilar entre `elevado` e não-`elevado` repetidamente, cada nova transição para `elevado` gera um
  novo alerta. Não há um intervalo mínimo artificial de horas entre notificações.
- Qualquer dado de FC/VFC/estresse saindo do dispositivo — esta fase introduz a primeira leitura de
  rede do pilar (a tolerância de notificação, abaixo), mas nenhuma escrita e nenhum dado de saúde
  trafega em nenhuma direção.
- Histórico de alertas anteriores na UI (ex.: uma lista "alertas recentes") — a notificação do
  sistema operacional já cumpre esse papel, o app não duplica esse registro.
- Alterar o `toleranciaNotificacao` a partir deste pilar — a preferência é só lida, nunca escrita,
  aqui (escrevê-la continua sendo responsabilidade exclusiva da tela de anamnese/Configurações já
  existente).

## Arquitetura

### Novo pacote

- `flutter_local_notifications`, adicionado às dependências do `mobile/pubspec.yaml`. É o único
  jeito de disparar uma notificação a partir do isolate de background do `workmanager` sem
  depender do app estar em primeiro plano — o mesmo isolate que já roda
  `biofeedbackCallbackDispatcher` (Fase 1) passa a também poder notificar.

### Detecção da transição

- `BiofeedbackSyncService.sincronizar()` (já existe, já calcula o novo `EstadoEstresse` a cada
  ciclo via `BiofeedbackStressDetector.detectar()`) passa a, **antes** de sobrescrever o resumo
  salvo no cache, ler o `estadoEstresse` do resumo **anterior** e compará-lo com o novo:
  - Se o anterior **não** era `elevado` (ou seja, era `calmo` ou `coletandoDados`, ou não havia
    resumo salvo ainda) **e** o novo é `elevado` → dispara o alerta.
  - Em qualquer outro caso (permanece `elevado`, permanece não-`elevado`, ou transiciona de
    `elevado` para outro estado) → não dispara.
- Essa decisão pura (dado o estado anterior, o novo estado, a flag de alertas ativos e a
  tolerância de notificação lida, decidir se deve notificar) vive numa função isolada,
  `deveAlertar({required EstadoEstresse? estadoAnterior, required EstadoEstresse estadoNovo, required bool alertasAtivos, required String? tolerancia})
  : bool`, sem nenhuma dependência de `flutter_local_notifications` nem de rede — testável com
  valores concretos, mesmo padrão das Fases 1 e 2. Retorna `true` somente quando:
  `estadoAnterior != EstadoEstresse.elevado && estadoNovo == EstadoEstresse.elevado && alertasAtivos && tolerancia == 'PADRAO'`.

### Tolerância de notificação

- A leitura de `toleranciaNotificacao` usa o `SensoryProfileRepository` já existente em
  `mobile/lib/features/onboarding/anamnese/sensory_profile_repository.dart` (o mesmo repositório
  que a tela de onboarding/Configurações já usa para ler e gravar o perfil sensorial). Só é
  chamado quando `deveAlertar` já teria retornado `true` pelas outras três condições (estado,
  toggle) — ou seja, só quando já se sabe que há uma transição real acontecendo, não a cada ciclo
  de sincronização — para minimizar chamadas de rede desnecessárias.
- Mesma regra usada hoje pelo backend para Gmail/Finanças (`backend/src/notifications/notification.service.ts`):
  só notifica se `tolerancia == 'PADRAO'`; qualquer outro valor (incluindo `null`/ausente) é
  tratado como silencioso.
- Esta é a única chamada de rede que este pilar passa a fazer. Continua sem nunca **enviar**
  FC/VFC/estresse — a leitura é de uma preferência do usuário que já existe e já é lida por outras
  partes do app.

### Notificação local

- Texto calmo, sem tom de alarme, título e corpo fixos (sem interpolação de números/valores):
  - Título: `"Um momento para respirar"`
  - Corpo: `"Sua frequência cardíaca está um pouco diferente do seu normal agora. Talvez seja um bom momento para uma pausa."`
- Payload da notificação: uma string simples (`'biofeedback_alerta'`) usada no callback de toque do
  `flutter_local_notifications` para decidir a navegação — mesmo papel do discriminador
  `data: {'tipo': 'email_triage'}` já usado nas notificações push de e-mail (`main.dart`), mas via
  o mecanismo de payload próprio deste pacote (diferente de FCM `data`).
- Toque na notificação (app fechado, em background, ou aberto) navega para `/biofeedback`.

## Modelo de dados e UI

- `BiofeedbackCache` ganha `getAlertasAtivos(): Future<bool>` (padrão `true`, mesmo padrão de
  default dos outros booleanos/ints já existentes no cache) e
  `setAlertasAtivos(bool): Future<void>`. `clear()` (desativar o Biofeedback) também remove essa
  chave, junto das demais.
- **Configurações:** novo `ListTile` com um `Switch`, rotulado "Alertas de estresse", logo abaixo
  de "Frequência do Biofeedback" — só visível quando o Biofeedback está ativo (mesmo padrão
  condicional já usado para "Desativar Biofeedback").
- Nenhuma mudança na Home nem na tela de detalhe além do que a Fase 2 já entrega — a notificação em
  si é a única superfície nova desta fase.

## Segurança e Privacidade

- Nenhum dado de FC/VFC/passos/treino/estresse trafega pela rede em nenhuma direção. A única
  chamada de rede desta fase é uma leitura (nunca escrita) da preferência `toleranciaNotificacao`
  já existente no perfil sensorial do próprio usuário — a mesma leitura que o backend já faz hoje
  para as notificações de Gmail/Finanças, só que agora feita a partir do dispositivo.
- A notificação em si não contém nenhum valor numérico de FC/VFC — o texto é fixo, então nenhuma
  informação de saúde aparece na tela de bloqueio/central de notificações do sistema operacional
  além do fato de que o app enviou uma notificação (mesmo nível de exposição que qualquer outra
  notificação do app já tem).
- Desativar os alertas (toggle em Configurações) ou desativar o Biofeedback inteiro para
  imediatamente qualquer notificação futura — não há fila/agendamento pendente para cancelar além
  do que a checagem em `sincronizar()` já resolve no próximo ciclo.

## Testes

- **`deveAlertar`** (função pura, nova): casos concretos cobrindo — transição `calmo → elevado`
  com alertas ativos e tolerância `'PADRAO'` → `true`; transição `coletandoDados → elevado` nas
  mesmas condições → `true`; `elevado → elevado` (já estava elevado) → `false`; `calmo → calmo`
  → `false`; `elevado → calmo` (saindo do estado elevado) → `false`; transição válida mas
  `alertasAtivos = false` → `false`; transição válida mas `tolerancia != 'PADRAO'` (incluindo
  `null`) → `false`; `estadoAnterior = null` (nenhum resumo salvo antes) combinado com
  `estadoNovo = elevado` → `true` (mesma regra de "não era elevado antes").
- **`BiofeedbackCache`**: `getAlertasAtivos`/`setAlertasAtivos` testados com fake de
  `SharedPreferencesAsync`, mesmo padrão já usado para os demais campos; `clear()` testado para
  confirmar que também apaga essa flag.
- **Verificação manual** (não automatizável em `flutter test`, mesma ressalva das fases
  anteriores): disparo real da notificação local a partir do isolate de background, toque na
  notificação navegando para a tela correta com o app em cada um dos três estados (fechado, em
  background, aberto), e o texto exibido na notificação — documentado como verificação manual
  necessária em dispositivo real antes de considerar a fase pronta.
