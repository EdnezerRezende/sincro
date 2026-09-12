# Finanças Assistidas — substituição da Pluggy por parsing heurístico de e-mail

## Contexto e objetivo

O Sincro é um app voltado a adultos autistas (nível 1 de suporte) com TDAH,
focado em reduzir sobrecarga executiva e ansiedade por meio de design calmo,
sem alarmismo e sem atrito cognitivo. O Pilar 4 (Finanças Generativas) usava
Open Finance via Pluggy, mas o piso mínimo do produto de Dados (R$ 2.500/mês)
é incompatível com a fase atual do projeto.

**Objetivo:** substituir a integração Pluggy por gestão financeira manual
potencializada por detecção heurística (100% Regex, sem LLM) de e-mails
bancários já sincronizados via Gmail pelo módulo `email-sync` existente, com
custo de infraestrutura zero.

**Entra nesta fase:**
- CRUD de Contas e Cartões de Crédito (gestão manual de saldo/limite).
- `EmailFinanceRegexParserService` plugado no `EmailSyncService` existente,
  gerando lançamentos em staging (`PENDENTE_REVISAO`).
- Fluxo de confirmação/ajuste do usuário — nada é lançado como oficial sem
  revisão humana.
- Recalculo do Saldo Livre reaproveitando o `SaldoLivreCalculator` já
  existente, sem alterações no calculator em si.
- Remoção completa do módulo Pluggy (backend e mobile).

**Fora de escopo (nesta fase):**
- OCR de PDF/imagem de fatura anexada — nunca será tentado; apenas metadado
  (remetente + data) é extraído quando não há valor no corpo do e-mail.
- Suporte a bancos/operadoras fora da lista inicial mapeada (lista é
  extensível depois, não abrangente no dia 1).
- Reconciliação automática de lançamento duplicado entre e-mail e lançamento
  manual já existente — o usuário decide na hora da revisão.
- Qualquer uso de LLM no pipeline de finanças.
- Repetição mensal de lançamentos fixos (`repeatMonths`, presente no
  `finance-app` de referência) — candidato a fase 2.

## Decisões (via brainstorming com o usuário)

1. **Corpo do e-mail:** o `email-sync` hoje só persiste o `snippet` do
   Gmail, não o corpo completo. O parser financeiro busca o corpo completo
   **sob demanda**, apenas para e-mails que batem um filtro de remetente
   financeiro conhecido, e **não persiste** esse corpo — extrai os dados e
   descarta. Menor custo de storage e menor superfície de dados sensíveis em
   repouso (LGPD).
2. **Migração de dados:** as tabelas atuais `FinanceConnection`,
   `FinanceAccount` (Pluggy) e `BoletoDda` (independente) são removidas via
   **drop limpo, sem migração de dados** — presume-se base de usuários
   pequena/zero em produção com essas tabelas povoadas, já que o piso da
   Pluggy nunca foi viável financeiramente.
3. **Integração do parser:** o `EmailFinanceRegexParserService` roda como
   **um novo passo inline no mesmo loop** do `EmailSyncService.syncUser`,
   reaproveitando o padrão arquitetural já usado pelos classificadores
   existentes (`HeuristicEmailClassifier`/`LlmEmailClassifier`), via import
   cruzado do `FinanceModule` no `EmailSyncModule`.

## Arquitetura e Fluxo de Dados

```
[Gmail API]
   │  (cron existente, EmailSyncScheduler)
   ▼
EmailSyncService.syncUser(user)
   │  para cada mensagem nova (via lastHistoryId):
   │  1. fetch metadata (remetente, assunto) — como hoje
   │  2. roda classificadores existentes (Heuristic/LlmEmailClassifier) — como hoje
   │  3. NOVO: EmailFinanceRegexParserService.match(remetente, assunto)
   │     → remetente/assunto bate lista de instituições financeiras conhecidas?
   │        não → segue fluxo normal, nada muda
   │        sim → busca corpo completo via GmailApiClient (chamada extra, só aqui)
   │              aplica regras de Regex (moeda, data, linha digitável)
   │              upsert em LancamentoFinanceiro (status=PENDENTE_REVISAO,
   │                origem=EMAIL_PARSER, emailMessageId=<id>) — idempotente
   │              corpo do e-mail é descartado da memória após o parse (não persiste)
   ▼
LancamentoFinanceiro (staging)
   │
   ▼
Usuário abre app → GET /financas/lancamentos?status=PENDENTE_REVISAO
   │
   ▼
Usuário confirma/ajusta → PATCH /financas/lancamentos/:id/confirmar
   │  status → CONFIRMADO (só aqui entra no cálculo)
   ▼
GET /financas/resumo → SaldoLivreCalculator (usa apenas CONFIRMADO)
```

## Modelagem de Dados (Prisma)

```prisma
enum TipoContaFinanceira {
  CORRENTE
  CARTEIRA
  POUPANCA
}

enum TipoLancamento {
  DESPESA
  RECEITA
  FATURA_CARTAO
}

enum StatusLancamento {
  PENDENTE_REVISAO
  CONFIRMADO
  IGNORADO
}

enum OrigemLancamento {
  EMAIL_PARSER
  MANUAL
}

model ContaFinanceira {
  id          String   @id @default(cuid())
  userId      String
  nome        String
  tipo        TipoContaFinanceira
  saldoAtual  Decimal  @db.Decimal(12, 2)
  cor         String?
  criadoEm    DateTime @default(now())
  atualizadoEm DateTime @updatedAt

  lancamentos LancamentoFinanceiro[]

  @@index([userId])
  @@map("contas_financeiras_v2")
}

model CartaoCredito {
  id             String   @id @default(cuid())
  userId         String
  nome           String
  diaFechamento  Int      // 1-31
  diaVencimento  Int      // 1-31
  limiteTotal    Decimal  @db.Decimal(12, 2)
  cor            String?
  criadoEm       DateTime @default(now())
  atualizadoEm   DateTime @updatedAt

  lancamentos    LancamentoFinanceiro[]

  @@index([userId])
  @@map("cartoes_credito")
}

model LancamentoFinanceiro {
  id               String            @id @default(cuid())
  userId           String
  tipo             TipoLancamento
  descricao        String
  valor            Decimal?          @db.Decimal(12, 2)
  dataVencimento   DateTime
  dataCompetencia  DateTime
  status           StatusLancamento  @default(PENDENTE_REVISAO)
  origem           OrigemLancamento
  isPago           Boolean           @default(false)
  emailMessageId   String?
  codigoBarras     String?
  cartaoId         String?
  contaId          String?
  criadoEm         DateTime          @default(now())
  atualizadoEm     DateTime          @updatedAt

  cartao           CartaoCredito?    @relation(fields: [cartaoId], references: [id])
  conta            ContaFinanceira?  @relation(fields: [contaId], references: [id])

  @@unique([userId, emailMessageId])
  @@index([userId, status])
  @@index([userId, dataVencimento])
  @@map("lancamentos_financeiros")
}
```

Notas de modelagem:
- `@@unique([userId, emailMessageId])` (em vez de unique global) garante
  idempotência por usuário sem impedir que dois usuários com o mesmo e-mail
  encaminhado gerem lançamentos distintos, e permite `emailMessageId` nulo em
  lançamentos manuais sem violar a constraint (Postgres trata múltiplos
  `NULL` como não-conflitantes em unique compostos).
- `valor` é `Decimal?` nullable propositalmente: cobre o caso de fatura por
  PDF/imagem sem valor extraído e o caso de ambiguidade no regex de moeda.
- Tabelas antigas (`FinanceConnection`, `FinanceAccount`, `BoletoDda`) e o
  módulo `pluggy/` são removidos na mesma migration (drop limpo, sem
  migração de dados).

## Endpoints REST (NestJS)

Novo módulo `backend/src/financas/`, substituindo `pluggy/` + `finance-sync/`.
Todas as rotas usam o `userId` do JWT (guard já existente) — nenhuma rota
aceita `userId` no path/body.

**Contas**
```
GET    /financas/contas
POST   /financas/contas                    { nome, tipo, saldoAtual, cor? }
PATCH  /financas/contas/:id
DELETE /financas/contas/:id                (bloqueia se houver lançamento vinculado)
```

**Cartões**
```
GET    /financas/cartoes
POST   /financas/cartoes                   { nome, diaFechamento, diaVencimento, limiteTotal, cor? }
PATCH  /financas/cartoes/:id
DELETE /financas/cartoes/:id               (bloqueia se houver lançamento vinculado)
```

**Lançamentos**
```
GET    /financas/lancamentos?status=PENDENTE_REVISAO&mes=2026-09
POST   /financas/lancamentos               cria lançamento manual (origem=MANUAL, status=CONFIRMADO direto)
PATCH  /financas/lancamentos/:id           edita campos
PATCH  /financas/lancamentos/:id/confirmar body { valor?, dataVencimento?, contaId?, cartaoId? } → status=CONFIRMADO
PATCH  /financas/lancamentos/:id/ignorar   status=IGNORADO (fica no histórico, não entra no cálculo)
DELETE /financas/lancamentos/:id           (só permitido se status ≠ CONFIRMADO)
```

**Resumo**
```
GET    /financas/resumo   { saldoLivre, saldoContas, faturasAbertas, despesasPendentesCiclo, cicloFim }
```

`PATCH .../confirmar` unifica "ajustar e confirmar" numa única chamada — bate
com o fluxo de UX ("abre o card, ajusta se necessário, confirma" é uma ação
só do ponto de vista do usuário).

## Motor de Regex

| Regra | Regex / lógica | Exemplo de e-mail | Fallback |
|---|---|---|---|
| Remetente/instituição | lista fixa e extensível de domínios/nomes (Nubank, Itaú, Inter, Bradesco, C6, Claro, Vivo, Enel, etc.) | `De: Nubank <fatura@nubank.com.br>` | remetente fora da lista → e-mail ignorado pelo parser |
| Valor (moeda BR) | `/R\$\s*([\d.]{1,3}(?:\.\d{3})*,\d{2})/` aplicado nas linhas ao redor de âncora semântica | `Valor total da fatura: R$ 1.234,56` | sem âncora ou múltiplos valores conflitantes → `valor: null` |
| Âncora semântica (prioridade) | ordem: `/valor\s+a\s+pagar/i`, `/total\s+da\s+fatura/i`, `/fatura\s+fechou/i`, `/total\s+a\s+pagar/i` | `Sua fatura de R$ 1.234,56 já está disponível` | nenhuma âncora bate → tenta `R$` isolado; se houver mais de um sem âncora, `valor: null` |
| Data (numérica) | `/(\d{2})\/(\d{2})\/(\d{4})/` | `Vencimento: 15/09/2026` | — |
| Data (por extenso) | `/(\d{1,2})\s+de\s+(janeiro\|...\|dezembro)\s+de\s+(\d{4})/i` | `Vence em 15 de setembro de 2026` | nenhum padrão bate → `dataVencimento` = recebimento do e-mail + regra padrão por instituição |
| Linha digitável (boleto, 47 dígitos) | `/^\d{5}\.\d{5}\s\d{5}\.\d{6}\s\d{5}\.\d{6}\s\d\s\d{14}$/m` | `34191.79001 01043.510047 91020.150008 1 84410000012345` | não bate → `codigoBarras: null`, sem bloqueio do lançamento |
| Linha digitável (concessionária, 48 dígitos) | `/^\d{11}-\d\s\d{11}-\d\s\d{11}-\d\s\d{11}-\d$/m` | `82660000001-2 23400012345-6 ...` | idem acima |
| Fatura sem valor extraível (PDF/imagem) | remetente conhecido + assunto `/fatura\s+fechou/i` sem `R$` no corpo | `Assunto: Sua fatura fechou` + link para PDF | cria lançamento com `valor: null`, `dataVencimento` por heurística de vencimento do cartão ou e-mail + N dias |
| Idempotência | `SELECT` por `[userId, emailMessageId]` antes de qualquer parse | — | reprocessamento nunca duplica |

## Mobile: UX

Três telas mockadas e aprovadas (canvas publicado, ver referência abaixo),
seguindo pixel a pixel os tokens de `mobile/lib/core/theme.dart` (cores
`#005A80`/`#4DD0E1` primária light/dark, fundo `#FAF8F5`/`#1A1F23`, fonte
Atkinson Hyperlegible, radius 16/12, bordas sutis) e adaptando — sem copiar
literalmente — o padrão de card de lançamento do `finance-app` de referência
ao tom calmo do Sincro (sem vermelho de alarme; urgência é `caution`
marrom-dourado/âmbar, nunca `error`):

1. **Card na Home** — resumo calmo do Saldo Livre + contagem não-alarmista
   de pendências ("3 lançamentos para revisar, sem pressa") + CTA "Ver
   finanças".
2. **Tela de Finanças** — AppBar + card de Saldo Livre em destaque + abas
   "Pendentes de revisão" / "Lançamentos do mês". Na aba de pendentes, cada
   card mostra descrição, âncora de origem ("sugestão automática"), valor
   (ou "informar valor" em itálico muted quando `null`) e ações
   Ignorar/Revisar. Na aba do mês, cards com borda esquerda colorida por
   urgência (`success`/`caution`, nunca `error`), reaproveitando o padrão
   visual já usado em `financas_screen.dart`/`home_screen.dart`.
3. **BottomSheet de confirmação** — aberto ao tocar "Revisar": campos
   pré-preenchidos (descrição, valor, vencimento, conta/cartão), uma linha
   explicativa não punitiva ("Dá uma conferida antes de confirmar — sem
   pressa"), e ações Ignorar/Confirmar.

Dark mode implementado com os valores reais do tema dark do Sincro
(`#4DD0E1` primária, `#1A1F23` fundo, `#2A2F35` superfície de card, `#66BB6A`/
`#FFB74D`/`#EF5350` para sucesso/atenção/erro).

**Referência viva:** canvas publicado com as 3 telas (claro/escuro
alternável por tweak) — https://claude.ai/code/artifact/e712b5ed-15e7-4c8a-b2e9-e20b38838b6f

**Ressalva registrada:** o tom exato de preenchimento interno
("surfaceContainerHighest") no dark mode foi inferido por extensão da
progressão de elevação Material (`#343A41`), pois o levantamento de tokens
só documentou 2 tons de superfície no tema dark do Flutter, não 3 como no
light — vale confirmar contra o `theme.dart` real antes da implementação
final do Flutter.

## Estratégia de Testes

**`EmailFinanceRegexParserService` (unitários, fixtures reais de e-mail)**

Fixtures em `backend/src/financas/parser/__fixtures__/`:

| Fixture | Cenário | Resultado esperado |
|---|---|---|
| `nubank-fatura-fechou-com-valor.txt` | Assunto "Sua fatura fechou" + "Total da fatura: R$ 1.234,56" | `valor=1234.56`, `dataVencimento` extraída, `tipo=FATURA_CARTAO` |
| `nubank-fatura-fechou-sem-valor.txt` | Mesmo assunto, corpo só com link para PDF | `valor=null`, `dataVencimento` por heurística do cartão |
| `itau-boleto-linha-digitavel.txt` | Linha digitável de 47 dígitos | `codigoBarras` extraído corretamente |
| `enel-conta-luz-48-digitos.txt` | Linha digitável de concessionária (48 dígitos) | `codigoBarras` extraído, `tipo=DESPESA` |
| `email-com-multiplos-valores-ambiguos.txt` | "limite disponível" e "valor a pagar" no mesmo corpo | `valor` = o que a âncora `valor a pagar` capturar |
| `email-remetente-desconhecido.txt` | Remetente fora da lista mapeada | parser ignora, não cria lançamento |
| `email-ja-processado-duplicado.txt` | Mesmo `emailMessageId` de um lançamento existente | segunda chamada não duplica (idempotência) |
| `data-por-extenso.txt` | "Vence em 15 de outubro de 2026" | `dataVencimento` = 2026-10-15 |

Cada teste chama `parser.match(fixture)` diretamente (regras determinísticas,
sem mockar regex) com mock apenas do Prisma para verificar `upsert`/idempotência.

**`SaldoLivreCalculator` (unitários — calculator em si não muda)**

Como o calculator já consome interfaces desacopladas (`ContaParaCalculo`,
`BoletoParaCalculo`), o teste central é de **contrato**: garantir que o novo
`FinanceResumoService` mapeia `LancamentoFinanceiro` (`status=CONFIRMADO`
apenas) corretamente antes de chamar `calcular()`. Casos:
- Lançamento `PENDENTE_REVISAO` não entra no cálculo, mesmo com vencimento no ciclo.
- Lançamento `IGNORADO` não entra no cálculo.
- Lançamento `CONFIRMADO` com `valor=null` é **excluído** do cálculo (não
  tratado como zero) — um valor não informado não deve distorcer o saldo.
- Fatura de cartão (`FATURA_CARTAO`) confirmada dentro do ciclo é subtraída corretamente.

**Isolamento multi-tenant (integração, e2e)**

- Usuário A não vê/edita/confirma lançamento, conta ou cartão de usuário B
  via nenhum endpoint, mesmo sabendo o `id`.
- Dois usuários processando mensagens com `emailMessageId` idêntico (e-mail
  encaminhado) geram lançamentos distintos — valida
  `@@unique([userId, emailMessageId])`.
- `GET /financas/resumo` calcula o Saldo Livre isoladamente por usuário, sem
  vazamento de saldo entre contas de tenants diferentes.

## Critérios de sucesso

- Módulo Pluggy (backend `src/pluggy/`, rotas de webhook, tabelas
  `FinanceConnection`/`FinanceAccount`/`BoletoDda`) completamente removido.
- `EmailFinanceRegexParserService` cria lançamentos em `PENDENTE_REVISAO`
  para pelo menos as instituições mapeadas no dia 1, sem duplicar em
  reprocessamento.
- Nenhum lançamento entra no cálculo de Saldo Livre sem confirmação humana.
- App mobile exibe as 3 telas do fluxo (card na Home, tela com abas,
  bottom sheet de confirmação) fiéis aos tokens visuais do Sincro, em claro
  e escuro.
- Suíte de testes das três frentes (parser, calculator/resumo, multi-tenant)
  passando.
