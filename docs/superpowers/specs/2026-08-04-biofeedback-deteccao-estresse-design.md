# Sincro — Biofeedback & Crise: Detecção de Estresse (Fase 2 deste pilar)

## Contexto

A Fase 1 deste pilar (`docs/superpowers/specs/2026-08-03-biofeedback-conexao-smartwatch-design.md`,
implementada e mesclada em `master`) deu ao usuário um card na Home e uma tela de detalhe mostrando
FC (frequência cardíaca) e VFC (variabilidade da frequência cardíaca) do dia, lidas do
HealthKit/Health Connect e mantidas inteiramente no dispositivo — sem qualquer análise ou detecção
de estresse.

Esta fase (Fase 2) adiciona a detecção em si: comparar as leituras recentes de FC/VFC, filtradas
para excluir períodos de atividade física, contra uma linha de base pessoal construída
automaticamente ao longo dos dias, e expor um estado de estresse simples ("Calmo" / "Elevado") na
Home e na tela de detalhe. A Fase 3 (alertas/intervenção quando um evento de estresse é detectado)
continua futura e fora de escopo aqui.

## Objetivo desta fase

Ao final desta fase, o usuário deve poder:

1. Ver, no card "💓 Biofeedback" da Home, o estado de estresse atual junto da FC mais recente (ex.:
   "72 bpm · Calmo"), quando a linha de base já estiver pronta.
2. Ver, na tela de detalhe (`/biofeedback`), uma linha "Estado atual: Calmo" / "Estado atual:
   Elevado" / "Coletando dados (N de 7 dias)", junto do resumo já existente (FC/VFC médias do dia).
3. Ter a linha de base pessoal (FC/VFC de repouso) construída automaticamente, sem nenhuma etapa
   manual de calibração, a partir do próprio histórico de uso do app.
4. Ter leituras feitas durante atividade física (treino registrado ou caminhada com passos)
   automaticamente excluídas do cálculo — tanto da linha de base quanto da detecção do dia — para
   não confundir FC elevada por exercício com estresse.

## Fora de escopo

- Qualquer alerta, notificação ou intervenção quando um estado "Elevado" é detectado — isso é a
  Fase 3 deste pilar.
- Persistência no backend — esta fase continua 100% on-device, como a Fase 1. Os agregados diários
  de repouso e a linha de base ficam só no cache local (`shared_preferences`), nunca sincronizados
  com `perfis_sensoriais` ou qualquer outro endpoint.
- Calibração manual de linha de base (ex.: pedir para o usuário ficar parado por N minutos) — a
  linha de base é sempre construída passivamente a partir do uso normal do app.
- Detecção de "picos" instantâneos de FC/VFC — a decisão desta fase compara **médias do período**
  (leituras em repouso do dia, agregadas), não leituras isoladas.
- Thresholds configuráveis pelo usuário — os parâmetros do algoritmo (janela de 14 dias, mínimo de
  7 dias para linha de base pronta, limiar de 15 passos, margem de 1,5 desvio-padrão) ficam fixos
  no código nesta fase.
- Qualquer métrica além de FC, VFC, passos e treinos (ex.: sono, SpO2).
- Estados de estresse graduados (ex.: leve/moderado/alto) — só binário "Calmo"/"Elevado", mais o
  estado transitório "Coletando dados", consistente com o tom calmo e não-alarmista do resto do
  app.

## Arquitetura

### Novos tipos de dado lidos

- Além de `HealthDataType.HEART_RATE` e a VFC específica da plataforma (já lidos na Fase 1), o app
  passa a solicitar permissão e ler também `HealthDataType.STEPS` e `HealthDataType.WORKOUT` no
  mesmo ciclo de sincronização (mesmo diálogo de permissão nativo, mesma chamada
  `requestAuthorization` da Fase 1, só com a lista de tipos ampliada).
- **A confirmar contra a versão resolvida do pacote `health`** (mesma cautela da Fase 1, que teve
  bugs reais de permissão/manifest descobertos só ao compilar de verdade): se ler `STEPS`/`WORKOUT`
  exige novas entradas em `AndroidManifest.xml` (ex. `android.permission.health.READ_STEPS`,
  `READ_EXERCISE`) além das já existentes (`READ_HEART_RATE`, `READ_HEART_RATE_VARIABILITY`), e se
  o `Info.plist` do iOS precisa de alguma chave adicional além do
  `NSHealthShareUsageDescription` já declarado. Isso vira um Prerequisite explícito no plano de
  implementação, verificado e ajustado durante a Task correspondente — não uma suposição do plano.

### "Em repouso": filtragem de atividade física

Uma leitura de FC ou VFC, no instante `t`, é considerada **em repouso** quando, simultaneamente:

1. Nenhuma sessão de `WORKOUT` ativa cobre `t` (isto é, não existe um treino com
   `inicio <= t <= fim` nos dados lidos do dia); **e**
2. A soma de passos (`STEPS`) no intervalo `[t - 2min30s, t + 2min30s]` (janela de 5 minutos
   centrada em `t`) é menor que 15.

Leituras que não satisfazem essas condições são descartadas tanto do cálculo da linha de base
quanto da detecção do dia corrente — elas continuam existindo no resumo de FC/VFC "do dia" já
mostrado pela Fase 1 (que não filtra por atividade), mas não entram na análise de estresse desta
fase.

### Linha de base pessoal

- Ao final de cada ciclo de sincronização, o app recalcula a média de FC e de VFC **em repouso**
  do dia corrente (a partir das leituras "hoje" já buscadas, filtradas pela regra acima) e grava
  (ou atualiza, se já existir) uma entrada `{data, mediaFcRepouso, mediaVfcRepouso}` do dia de hoje
  numa janela local — uma lista guardada no cache local, ordenada por data, contendo no máximo os
  últimos **14 dias** (entradas mais antigas que isso são descartadas a cada gravação).
- Se o dia corrente não teve nenhuma leitura em repouso ainda, nenhuma entrada é gravada/atualizada
  para hoje (evita contaminar a janela com um dia "zerado" só porque a sincronização rodou cedo).
- A **linha de base** é a média (`μ`) e o desvio-padrão (`σ`) de `mediaFcRepouso` e de
  `mediaVfcRepouso` calculados sobre as entradas da janela, **excluindo a entrada de hoje** (a
  linha de base compara o dia atual contra dias anteriores, nunca contra si mesmo).
- A linha de base só é considerada **pronta** quando a janela tem pelo menos **7 entradas** (dias)
  anteriores a hoje. Antes disso, o estado é `coletandoDados`.

### Detecção

Com a linha de base pronta e havendo pelo menos uma leitura em repouso hoje, o estado é:

- **`elevado`** se `mediaFcRepousoHoje >= μ_fc + 1,5·σ_fc` **E**
  `mediaVfcRepousoHoje <= μ_vfc - 1,5·σ_vfc` (as duas condições precisam valer juntas — FC alta
  sozinha, ou VFC baixa sozinha, não bastam; isso reduz falso positivo, já que qualquer uma das
  duas métricas isoladamente é ruidosa).
- **`calmo`** caso contrário (linha de base pronta, mas as condições acima não se confirmam).
- **`coletandoDados`** se a linha de base ainda não está pronta (menos de 7 dias de histórico), ou
  se não há nenhuma leitura em repouso hoje ainda para comparar.

Se `σ_fc` ou `σ_vfc` for zero (variância nula, ex. poucos dias com valores idênticos), a condição
correspondente nunca é satisfeita (evita divisão por zero e falsos positivos por uma linha de base
degenerada com pouquíssima variação real).

Toda essa lógica vive num novo `BiofeedbackStressDetector`, uma classe pura (sem I/O, sem
`health`, sem `shared_preferences`) que recebe as leituras já buscadas e o histórico já lido do
cache e devolve o estado — mesmo padrão do `BiofeedbackSummaryCalculator` da Fase 1, testável com
listas concretas.

### Ciclo de sincronização

`BiofeedbackSyncService.sincronizar()` (já existente) passa a, no mesmo ciclo:

1. Ler FC, VFC, passos e treinos do dia (via `BiofeedbackHealthService`, ampliado).
2. Calcular o resumo do dia (como já fazia na Fase 1, sem filtragem — isso não muda).
3. Ler o histórico de repouso do cache, calcular a linha de base, filtrar as leituras de hoje por
   "em repouso", rodar o `BiofeedbackStressDetector` e obter o estado.
4. Gravar: o resumo do dia (já existente, agora com o campo `estadoEstresse` adicionado) e a
   entrada/atualização do histórico de repouso de hoje.

## Modelo de dados e armazenamento local

- `BiofeedbackSummary` (já existe) ganha um campo novo: `estadoEstresse` (enum
  `EstadoEstresse { calmo, elevado, coletandoDados }`), serializado em `toJson()`/`fromJson()`
  como os demais campos.
- Novo tipo `DiaRepouso { data: DateTime (só a parte da data, sem hora), mediaFcRepouso: double,
  mediaVfcRepouso: double }`.
- `BiofeedbackCache` (já existe) ganha `getHistoricoRepouso(): Future<List<DiaRepouso>>` (lista
  vazia se nada gravado ainda) e `setHistoricoRepouso(List<DiaRepouso>): Future<void>`, seguindo o
  mesmo padrão `SharedPreferencesAsync` + JSON já usado pelo resumo (a Fase 1 migrou o cache para
  `SharedPreferencesAsync` justamente para background/foreground verem os mesmos dados — este
  histórico usa a mesma instância).
- `clear()` (desativar Biofeedback) também apaga o histórico de repouso, junto do resumo e da
  flag de ativação já apagados hoje — nenhum dado de FC/VFC/passos/treino sobrevive à
  desativação.

Nenhum dado sai do dispositivo — mesma garantia de privacidade da Fase 1: sem chamada de rede, sem
DTO, sem endpoint de backend.

## Mobile: UI

- **Home** (`_BiofeedbackCard`, já existe): quando ativado e com FC disponível, o subtítulo passa a
  incluir o estado, ex. `"72 bpm · Calmo"` ou `"72 bpm · Elevado"`. Quando o estado é
  `coletandoDados`, a Home mostra só a FC (`"72 bpm"`), sem mencionar coleta de dados — evitar que
  a tela de primeiro contato do app pareça ter uma "pendência". Sem cor, sem ícone de alerta — só
  texto, mesmo padrão calmo do resto do card.
- **Tela de detalhe** (`biofeedback_screen.dart`, já existe): nova linha abaixo dos cards de
  FC/VFC médias, mostrando "Estado atual: Calmo", "Estado atual: Elevado" ou
  "Coletando dados (N de 7 dias)" (N = quantidade de dias já na janela, até 7). Texto simples, sem
  gráfico, sem cor — mesma linguagem visual dos números já existentes na tela.
- **Configurações:** nenhuma mudança nesta fase — os parâmetros do algoritmo não são
  configuráveis.

## Segurança e Privacidade

- Mesma garantia da Fase 1: nenhum dado de FC/VFC/passos/treino trafega pela rede ou toca o
  backend. A linha de base e o estado de estresse são inteiramente derivados e mantidos no
  dispositivo.
- O texto de uso de dados de saúde (`NSHealthShareUsageDescription`, permissões do Health Connect)
  deve ser atualizado para mencionar também passos e treinos, já que agora são lidos além de
  FC/VFC.
- Desativar o Biofeedback apaga o histórico de repouso e a linha de base junto com o resumo — nada
  de FC/VFC/passos/treino permanece armazenado pelo Sincro após a desativação.

## Testes

- **`BiofeedbackStressDetector`** (novo, puro): casos concretos cobrindo — linha de base não
  pronta (menos de 7 dias de histórico) → `coletandoDados`; linha de base pronta mas sem leitura em
  repouso hoje → `coletandoDados`; FC e VFC dentro da faixa normal → `calmo`; FC elevada mas VFC
  normal (só uma condição) → `calmo`; FC e VFC ambas fora da faixa → `elevado`; desvio-padrão zero
  em uma métrica → não deve gerar `elevado` por essa métrica.
- **Filtragem "em repouso"** (dentro do detector ou de um helper puro dedicado): leitura durante
  treino ativo é descartada; leitura com passos acima do limiar na janela de 5 minutos é
  descartada; leitura sem treino e sem passos próximos é mantida.
- **`BiofeedbackCache`**: `getHistoricoRepouso`/`setHistoricoRepouso` testados com fake de
  `SharedPreferencesAsync`, mesmo padrão já usado para o resumo; `clear()` testado para confirmar
  que também apaga o histórico.
- **Verificação manual** (não automatizável em `flutter test`, mesma ressalva da Fase 1): diálogo
  de permissão ampliado (FC + VFC + passos + treino), leitura real de `STEPS`/`WORKOUT` do
  HealthKit/Health Connect, e o estado mudando de fato ao longo de vários dias de uso — documentado
  como verificação manual necessária em dispositivo real, com histórico acumulado ao longo de pelo
  menos uma semana, antes de considerar a fase pronta.
