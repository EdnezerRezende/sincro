# Sincro — Biofeedback & Crise: Conexão com Smartwatch (Fase 1 deste pilar)

## Contexto

O Sincro é um app voltado para adultos autistas nível 1 de suporte, com foco em reduzir a carga
executiva e a ansiedade do dia a dia. Fase 1 (onboarding, anamnese, rede de apoio), Gestão
Executiva — Triagem de E-mail e Finanças Generativas estão implementadas e revisadas. O spec
original (`docs/superpowers/specs/2026-08-01-onboarding-anamnese-rede-apoio-design.md`) lista
"Biofeedback & Crise" como o terceiro dos cinco próximos sub-projetos, com o escopo "integração
com smartwatch (HealthKit/Health Connect), filtragem de falsos positivos, alertas de
descompressão" — e já antecipava que o registro `perfis_sensoriais` cresceria para guardar
"limiares de estresse do smartwatch" em uma fase futura.

Assim como o pilar de e-mail, este pilar é fatiado em fases menores — as três partes do escopo
original são interdependentes (a filtragem faz parte do pipeline de detecção, e os alertas são a
saída desse pipeline), então cada uma vira sua própria fase:

1. **Fase 1 (este documento):** conectar o smartwatch e mostrar um resumo calmo de frequência
   cardíaca (FC) e variabilidade da frequência cardíaca (VFC) — sem nenhuma detecção de estresse
   ainda.
2. **Fase 2 (spec futura):** algoritmo de detecção de estresse com filtragem de falsos positivos
   por atividade física.
3. **Fase 3 (spec futura):** alertas de descompressão / intervenção quando um evento de estresse
   é detectado.

## Objetivo desta fase

Ao final desta fase, o usuário deve poder:

1. Ativar o Biofeedback a partir de um novo card na Home, concedendo permissão de leitura de FC e
   VFC ao HealthKit (iOS) ou Health Connect (Android).
2. Ver, nesse card, a leitura de FC mais recente; numa tela de detalhe, ver a FC e VFC médias do
   dia — sem gráficos, só números calmos.
3. Escolher a frequência de atualização em background (15 min / 30 min / 1 hora / 2 horas) nas
   Configurações, mudável a qualquer momento.
4. Desativar o Biofeedback a qualquer momento, o que cancela a leitura em background e apaga o
   cache local.

## Fora de escopo

- Qualquer detecção de estresse ou algoritmo de análise sobre os dados de FC/VFC — esta fase só
  captura e exibe (fica para a Fase 2 deste pilar).
- Filtragem de falsos positivos por atividade física (Fase 2).
- Alertas de descompressão ou qualquer intervenção/notificação (Fase 3).
- Persistência no backend — nada de FC/VFC sai do celular nesta fase. Este é o primeiro pilar do
  Sincro sem nenhuma mudança no backend.
- Entrega em background nativa do HealthKit (`enableBackgroundDelivery`) — mais responsiva que
  polling periódico, mas só compensa a complexidade quando houver um alerta de fato para disparar
  (Fase 3). O Health Connect no Android não tem um mecanismo equivalente robusto, então usar
  `enableBackgroundDelivery` agora criaria uma implementação assimétrica entre plataformas sem
  benefício correspondente nesta fase.
- Suporte a métricas além de FC/VFC (passos, sono, etc.).
- Calibração de limiares pessoais de estresse — o `perfis_sensoriais` só passa a guardar isso
  quando a Fase 2 (detecção) existir de fato.

## Arquitetura

### Permissão e leitura

- O pacote `health` (pub.dev) fornece uma API única para solicitar permissão e ler FC/VFC tanto
  do HealthKit (iOS) quanto do Health Connect (Android), evitando integração nativa separada por
  plataforma.
- Ativar o Biofeedback dispara o diálogo de permissão nativo do sistema operacional — não é um
  fluxo OAuth como Gmail/Pluggy, é uma permissão local do dispositivo. Se o usuário negar, o app
  trata como "sem dados disponíveis", sem bloquear nenhuma outra funcionalidade.
- Ao ativar, o app faz uma leitura inicial imediata (síncrona, bloqueando só o próprio card em
  loading) para o resumo não ficar vazio até o primeiro ciclo de background rodar.

### Cache local e background

- O pacote `workmanager` agenda uma tarefa periódica que relê FC/VFC via `health` e grava um
  resumo — última leitura de FC, médias do dia de FC e VFC, timestamp da última atualização — num
  cache local (`shared_preferences`; o volume de dados é pequeno o suficiente para não justificar
  um banco local como Hive/sqlite).
- O card da Home e a tela de detalhe leem **só do cache local**, nunca direto do `health` — evita
  releituras repetidas a cada rebuild de UI e mantém a UI responsiva mesmo se a leitura do
  HealthKit/Health Connect for lenta.
- A frequência escolhida nas Configurações é passada ao `workmanager` ao (re)agendar a tarefa;
  trocar a frequência cancela a tarefa anterior e agenda uma nova com o novo intervalo.
- **Limitação conhecida:** o timing real de execução em background depende do sistema
  operacional — Android com otimização agressiva de bateria (comum em alguns fabricantes, ex.
  Xiaomi/Huawei) pode atrasar ou pular execuções; isso é esperado e não deve ser tratado como bug
  nesta fase. O mínimo técnico de intervalo em ambas as plataformas é de aproximadamente 15
  minutos — por isso a frequência é oferecida como uma lista de opções pré-definidas (15 min / 30
  min / 1 hora / 2 horas), não um campo numérico livre que daria uma falsa sensação de precisão.

### Desativar

- Cancela a tarefa do `workmanager` e apaga o cache local (`shared_preferences`).
- A permissão do sistema operacional em si não pode ser revogada programaticamente pelo app (nem
  HealthKit nem Health Connect permitem isso) — a tela de Configurações deixa claro que
  "desativar" para de ler os dados no Sincro, mas a permissão do SO continua concedida até o
  usuário revogá-la manualmente nas configurações do sistema, se desejar.

## Mobile: UI

- **Home:** novo card "💓 Biofeedback":
  - Se não ativado (ou permissão negada): CTA "Ativar Biofeedback", com uma frase curta
    explicando o benefício (ex.: "Acompanhe seu bem-estar com seu smartwatch").
  - Se ativado e com dados: mostra a FC mais recente (ex.: "72 bpm agora"), navegando para a tela
    de detalhe.
  - Se ativado mas sem nenhuma leitura ainda (ex.: sem smartwatch pareado): mensagem neutra
    "Nenhum dado disponível ainda" — sem parecer erro.
- **Tela de detalhe** (`/biofeedback`, nova): FC média do dia, VFC média do dia, horário da
  última atualização. Pull-to-refresh dispara uma releitura sob demanda, além do ciclo em
  background.
- **Configurações:**
  - Seletor de frequência de atualização em background (15 min / 30 min / 1 hora / 2 horas),
    mesmo padrão de UI de escolha única já usado no app.
  - Opção "Desativar Biofeedback", com confirmação antes (mesmo padrão de desconectar
    Gmail/Finanças) — apaga o cache local e cancela a tarefa em background.

## Segurança e Privacidade

- Nenhum dado de FC/VFC trafega pela rede ou toca o backend nesta fase — permanece inteiramente
  no dispositivo (HealthKit/Health Connect + cache local `shared_preferences`).
- O app declara o uso de dados de saúde nos manifestos da plataforma
  (`NSHealthShareUsageDescription` no iOS `Info.plist`; permissões de Health Connect no
  `AndroidManifest.xml`), com texto explicando o propósito de forma clara, exigido pelas lojas de
  app.
- Desativar apaga o cache local imediatamente — nenhum dado de FC/VFC permanece armazenado pelo
  Sincro após a desativação (a permissão do SO em si, como já dito, só o usuário revoga
  manualmente).

## Testes

- **Mobile:**
  - Repositório/serviço que envolve o pacote `health`: testado com uma abstração/fake da leitura
    de dados — o pacote `health` não é facilmente mockável via Dio como os outros repositórios
    deste app, então a testagem foca na lógica de transformação dos dados brutos em resumo, não
    na chamada real à plataforma.
  - Lógica de cálculo de médias do dia a partir de uma lista de leituras: testada isoladamente
    com casos concretos (lista vazia, uma leitura, múltiplas leituras).
  - Cache local (leitura/escrita do resumo): testado com um fake de `SharedPreferences` (o
    pacote oferece `SharedPreferences.setMockInitialValues` para isso).
- **Verificação manual** (não automatizável em `flutter test`, mesma situação do WebView do
  pilar de Finanças): diálogo de permissão nativo, agendamento real do `workmanager`, e
  comportamento em background — documentados como verificação manual necessária em dispositivo
  real antes de considerar a fase pronta, já que simuladores/emuladores frequentemente não
  refletem o comportamento real de otimização de bateria.
