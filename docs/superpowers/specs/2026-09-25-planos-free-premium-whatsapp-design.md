# Planos Free e Premium + Lançamentos Financeiros via WhatsApp

> **Status:** rascunho para validação — nada implementado ainda.
> As decisões marcadas com **[VALIDAR]** precisam de confirmação antes do plano de implementação.

## Contexto e objetivo

O Sincro é um app para adultos autistas (nível 1 de suporte) com TDAH, focado em
reduzir sobrecarga executiva e ansiedade. Hoje todo usuário tem acesso a tudo, e
o custo variável do produto cresce com o uso de IA (Claude) e, em breve, com a
integração de WhatsApp.

**Objetivo:** introduzir dois planos — **Free** e **Premium** — com um mecanismo
de *entitlements* (direitos de uso) centralizado no backend, e lançar como
primeira funcionalidade exclusiva do Premium o **registro de lançamentos
financeiros pelo WhatsApp** ("gastei 45,90 no mercado").

### O que já existe no código (ponto de partida)

| Item | Onde | Situação |
|------|------|----------|
| Campo `plano` no usuário | `backend/prisma/schema.prisma` → `User.plano String @default("simples")` | Existe, mas é string livre e **nada no app define `"pro"`** |
| Gate de plano | `backend/src/email-sync/email-sync.service.ts:124` | `plano === 'pro'` → `LlmEmailClassifier`; senão `HeuristicEmailClassifier` |
| Chamadas pagas ao Claude | `email-draft.service.ts`, `email-commitment-extraction.service.ts`, `llm-email-classifier.service.ts` (Haiku 4.5), `rag.service.ts` | Rascunhos e compromissos **não têm gate** hoje |
| Lançamentos financeiros | `financas/` → `LancamentoFinanceiro` com `OrigemLancamento { EMAIL_PARSER, MANUAL }` | Fluxo staging (`PENDENTE_REVISAO`) → confirmação → evento no Google Agenda |
| Extratores de valor/data | `financas/parser/finance-extractors.ts` | Reaproveitáveis para interpretar mensagens de WhatsApp |
| WhatsApp hoje | `emergency.service.ts` | Só links `wa.me` para contatos de confiança (sem API, sem custo) |
| Admin | `User.isAdmin` + `AdminGuard` | Pode servir de base para concessões manuais de plano |

---

## Princípios de produto (propostos)

1. **Segurança nunca tem paywall.** Tudo que serve a um momento de crise ou
   sobrecarga — Emergência, Rede de apoio, Grounding cards, Jogos calmantes,
   alertas de estresse do Biofeedback, busca de Profissionais — é **sempre Free
   e sem limites**. Para o público do Sincro, esse é um requisito ético, não
   só comercial.
2. **O Premium vende redução de esforço, não acesso.** O Free é um app completo
   e útil feito à mão; o Premium automatiza (IA, e-mail, WhatsApp, agenda).
3. **O gate acompanha o custo.** O que tem custo marginal por uso (LLM, API do
   WhatsApp, sincronização frequente) é Premium ou tem cota; o que roda no
   aparelho ou é CRUD barato fica no Free.
4. **Paywall calmo.** Sem contagem regressiva, sem vermelho, sem "última
   chance", sem pop-up surpresa. O convite ao Premium só aparece **no ponto de
   uso** (ao tocar numa função Premium) e **nunca** durante um alerta de
   estresse ou fluxo de emergência. Sempre há um "agora não" visível.
5. **Rebaixar o plano nunca apaga dados.** Ao voltar para o Free, tudo que foi
   criado continua visível e editável; só as automações param.

---

## Separação de funcionalidades (proposta) **[VALIDAR]**

Legenda: ✅ incluído · 🔢 com limite · — não incluído

### Bem-estar e segurança (sempre Free)

| Funcionalidade | Free | Premium |
|---|---|---|
| Botão de emergência + mensagens para contatos (`wa.me`) | ✅ | ✅ |
| Rede de apoio (contatos de confiança) | ✅ | ✅ |
| Grounding cards + favoritos | ✅ | ✅ |
| Jogos calmantes (Voo Sereno, Estrada Tranquila) | ✅ | ✅ |
| Busca de profissionais | ✅ | ✅ |
| Onboarding, perfil sensorial, Guia do app | ✅ | ✅ |
| Biofeedback: leitura FC/HRV, gráfico diário, alertas de estresse, sugestão de card | ✅ | ✅ |

> Biofeedback roda no aparelho (HealthKit/Health Connect) e não tem custo de
> servidor — não há motivo econômico para cobrar por ele, e os alertas são
> parte da proteção contra crise.

### Finanças

| Funcionalidade | Free | Premium |
|---|---|---|
| Lançamentos manuais (criar/editar/confirmar) | ✅ ilimitado | ✅ |
| Resumo / Saldo Livre | ✅ | ✅ |
| Contas financeiras | 🔢 até 2 | ✅ ilimitado |
| Cartões de crédito | 🔢 até 1 | ✅ ilimitado |
| Detecção automática de contas/faturas pelo e-mail (parser regex) | — | ✅ |
| Vencimentos confirmados viram evento no Google Agenda | — | ✅ |
| **Lançamento via WhatsApp** | — | ✅ |

### Gestão executiva (e-mail e agenda)

| Funcionalidade | Free | Premium |
|---|---|---|
| Conectar Gmail + triagem (inbox "Precisa de atenção") | ✅ classificador heurístico | ✅ classificador com IA |
| Frequência de sincronização do Gmail | a cada 30 min | a cada 2 min (atual) |
| Rascunhos de resposta com IA | 🔢 5/mês (degustação) | ✅ (cota de uso justo, ex.: 300/mês) |
| Extração de compromissos do e-mail → agenda | — | ✅ |
| Agenda: leitura e categorias | ✅ | ✅ |

**Alternativas para discutir:**
- (A) *Proposta acima:* e-mail e agenda básicos no Free, IA no Premium.
- (B) Mais agressiva: Gmail inteiro só no Premium — Free fica só com finanças manuais + bem-estar.
- (C) Mais generosa: detecção de finanças por e-mail também no Free (é regex, custo quase zero) e só IA + WhatsApp no Premium.

Minha recomendação é **(A)**: o parser regex tem custo baixo, mas é justamente o
que mais "tira trabalho" do usuário — é um bom motivo para assinar junto com o
WhatsApp.

---

## Arquitetura de entitlements (backend)

### Modelo de dados

```prisma
enum Plano {
  FREE
  PREMIUM
}

enum StatusAssinatura {
  TRIAL
  ATIVA
  EM_CARENCIA      // falha de pagamento, loja ainda tentando cobrar
  CANCELADA        // não renova, mas vale até expiraEm
  EXPIRADA
}

model User {
  // ...
  plano       Plano        @default(FREE)   // cache derivado da assinatura; fonte da verdade é Assinatura
  assinatura  Assinatura?
}

model Assinatura {
  id                String           @id @default(uuid())
  userId            String           @unique @map("user_id")
  user              User             @relation(fields: [userId], references: [id])
  provedor          String           // 'revenuecat' | 'concessao_manual'
  produtoId         String?          @map("produto_id")      // ex.: sincro_premium_mensal
  status            StatusAssinatura
  expiraEm          DateTime?        @map("expira_em")
  idExterno         String?          @unique @map("id_externo") // app_user_id / original_transaction_id
  atualizadoEm      DateTime         @updatedAt @map("atualizado_em")
  criadoEm          DateTime         @default(now()) @map("criado_em")

  @@map("assinaturas")
}

model UsoMensal {
  userId    String @map("user_id")
  recurso   String            // 'rascunho_ia' | 'whatsapp_lancamento' | ...
  mes       String            // 'YYYY-MM'
  contagem  Int    @default(0)

  @@id([userId, recurso, mes])
  @@map("uso_mensal")
}
```

**Migração:** converter `plano String` → `enum Plano` mapeando `'simples' → FREE`
e `'pro' → PREMIUM`. Atualizar o gate em `email-sync.service.ts:124` para
`user.plano === Plano.PREMIUM` (ou, melhor, `entitlements.pode(user, 'email_classificacao_ia')`).

### Serviço e guard

- `backend/src/planos/` (novo módulo):
  - `entitlements.ts` — **tabela única** `Recurso → { free, premium }` (booleano
    ou cota numérica). É o único lugar onde a separação da seção anterior vive
    em código.
  - `EntitlementsService`
    - `pode(userId, recurso): Promise<boolean>`
    - `consumir(userId, recurso)` — incrementa `UsoMensal` de forma atômica
      (`upsert` + `increment`) e lança `PlanoLimiteException` se a cota estourou.
    - `resumo(userId)` — plano, status, expiração e cotas restantes.
  - `@RequerRecurso('whatsapp_lancamento')` + `EntitlementsGuard` — decorator
    para controllers, no mesmo estilo do `AdminGuard`.
  - `PlanoLimiteException` → HTTP **402 Payment Required** com corpo
    `{ codigo: 'PLANO_NECESSARIO', recurso, plano_necessario: 'PREMIUM' }`.
    O mobile intercepta esse código no Dio e abre o convite ao Premium.
- `GET /users/me/plano` → `{ plano, status, expiraEm, recursos: {...}, cotas: {...} }`.
- **Admins são sempre Premium**; concessões manuais (testadores do Firebase App
  Distribution, amigos, parceiros) usam `provedor = 'concessao_manual'` com
  `expiraEm`.

### Pontos de gate no código atual

| Recurso | Onde aplicar |
|---|---|
| `email_classificacao_ia` | `EmailSyncService.syncUser` (substitui o `plano === 'pro'`) |
| `rascunho_ia` (cota) | `EmailReplyController` `POST :id/rascunhos` |
| `compromissos_agenda` | `EmailReplyController` `POST compromissos/confirmar` + extração |
| `financas_deteccao_email` | `FinanceEmailProcessor` (pular para Free) |
| `financas_agenda` | `FinanceCalendarSyncService` (pular para Free) |
| `contas_limite` / `cartoes_limite` | `ContasService.create` / `CartoesService.create` |
| `sync_frequente` | `EmailSyncScheduler` — Free sincroniza em janela de 30 min |
| `whatsapp_lancamento` | Webhook do WhatsApp (seção abaixo) |

---

## Cobrança

Assinaturas de conteúdo digital vendidas dentro do app **precisam** usar Google
Play Billing e Apple In-App Purchase (regras das lojas).

**Recomendação: RevenueCat** **[VALIDAR]**
- SDK Flutter (`purchases_flutter`) cuida da compra, restauração e das
  diferenças Play/App Store.
- Webhook do RevenueCat → `POST /planos/webhook/revenuecat` (autenticado por
  header secreto) → atualiza `Assinatura` e o cache `User.plano`.
- `app_user_id` do RevenueCat = `User.id` do Sincro.
- Gratuito até um faturamento mensal baixo (conferir limite atual na página de
  preços) — adequado à fase atual.
- Alternativa sem terceiros: pacote `in_app_purchase` + validação de recibo no
  backend (Google Play Developer API + App Store Server API). Mais trabalho e mais
  casos de borda (renovação, reembolso, carência).

**Web (Flutter Web no sandbox):** sem compra na web na fase 1; o usuário vê o
plano, mas assina pelo celular. Stripe fica para depois se a web virar canal.

**Produtos sugeridos:** `sincro_premium_mensal` e `sincro_premium_anual`, com
**14 dias de teste grátis**. Preço **[VALIDAR]** — sugestão para discutir:
R$ 14,90/mês ou R$ 119,90/ano.

---

## Mobile

- `planoProvider` (Riverpod, `AsyncNotifier`) lendo `GET /users/me/plano`;
  recarrega ao voltar ao primeiro plano e após compra.
- Widget `RecursoPremium(recurso: ..., child: ..., bloqueado: ...)` para
  esconder/mostrar ou marcar com um selo discreto "Premium".
- Interceptor no Dio: resposta 402 `PLANO_NECESSARIO` → abre `ConhecaPremiumSheet`.
- `features/planos/`:
  - `conheca_premium_screen.dart` — lista curta do que muda, preço claro, botão
    "Começar teste de 14 dias" e "Agora não" com o mesmo peso visual.
  - `meu_plano_screen.dart` (em Configurações) — plano atual, renovação,
    "Gerenciar assinatura" (abre a loja), "Restaurar compras".
- Textos seguem o tom calmo do app (sem "Desbloqueie já!", sem urgência).

---

## WhatsApp — lançamentos financeiros (Premium)

### Experiência

```
Usuário:  gastei 45,90 no mercado no nubank
Sincro:   Anotei assim:
          • Despesa · R$ 45,90
          • Mercado · Conta: Nubank · Hoje (25/09)
          [Confirmar]  [Corrigir no app]  [Descartar]
Usuário:  (toca Confirmar)
Sincro:   Pronto, está no seu Sincro. ✓
```

Outros exemplos que a fase 1 precisa entender:
- `paguei a luz 187,32 ontem` → despesa, data de ontem, `isPago = true`
- `recebi 3200 de salário` → receita
- `netflix 55,90 dia 10 no cartão` → despesa no cartão, vencimento dia 10
- `resumo` / `saldo` → responde o Saldo Livre do mês (reaproveita `SaldoLivreCalculator`)
- `desfazer` → apaga o último lançamento criado pelo WhatsApp (até 10 min)
- `ajuda` → exemplos curtos
- `parar` → desvincula o número

Mensagens curtas, sem emojis em excesso, respeitando `tomPreferido` do perfil
sensorial quando fizer sentido.

### Provedor

**WhatsApp Business Cloud API (Meta), direto** — sem intermediário (Twilio,
Z-API etc.).
- Evita a margem do intermediário e APIs não oficiais (risco de banimento).
- Como é **sempre o usuário que inicia** a conversa, as respostas do bot caem
  na janela de atendimento de 24h. Pelo modelo de preços da Meta em vigor, essas
  respostas não são cobradas (conferir a tabela atual para o Brasil antes do
  lançamento). Mensagens proativas (ex.: "sua conta vence amanhã") exigiriam
  *templates* pagos — **fora da fase 1**.
- Pré-requisitos: conta Meta Business verificada, número dedicado, nome de
  exibição aprovado ("Sincro"), app no Meta for Developers com o produto WhatsApp.

### Vinculação do número (verificação reversa)

1. No app (Premium): **Finanças → Lançar pelo WhatsApp → Vincular**.
2. Backend gera um código de 6 dígitos (validade 10 min) e o app mostra um botão
   que abre `https://wa.me/<numero_sincro>?text=SINCRO%20<codigo>`.
3. O usuário só toca em enviar. O webhook recebe a mensagem, confere o código e
   vincula **o número de onde a mensagem veio** ao usuário.
4. O bot responde confirmando, com 2–3 exemplos de uso.

Vantagens: não precisa de SMS/OTP pago, o número é comprovadamente do usuário e
a conversa já começa aberta pelo usuário.

### Interpretação da mensagem (híbrida)

1. **Regex primeiro** — reaproveita `finance-extractors.ts` (valor em BRL,
   datas relativas "hoje/ontem/dia 10") + dicionário de verbos
   (`gastei|paguei|comprei` → DESPESA; `recebi|ganhei|entrou` → RECEITA) +
   casamento aproximado do nome de conta/cartão do usuário
   (`common/text-match.util.ts`).
2. **Claude Haiku 4.5 como fallback**, só quando o regex não fecha valor + tipo,
   usando *tool use* com esquema estrito (`tipo`, `valor`, `descricao`,
   `data`, `contaNome?`, `cartaoNome?`, `confianca`). Mesmo modelo já usado no
   projeto (`claude-haiku-4-5-20251001`).
3. Se ainda faltar algo essencial (valor), o bot pergunta **uma coisa por vez**
   ("Qual foi o valor?") — no máximo 2 perguntas, depois sugere "Corrigir no app".

### Status do lançamento **[VALIDAR]**

O pipeline de finanças segue "nada vira oficial sem revisão humana". Proposta:
- Lançamento criado com `origem = WHATSAPP` e `status = PENDENTE_REVISAO`.
- Botão **Confirmar** no WhatsApp = revisão humana → `CONFIRMADO` (+ evento na
  agenda, igual à confirmação no app).
- Se o usuário não tocar em nada, o lançamento fica pendente no app, como os
  vindos de e-mail.

Alternativa: confirmar direto sem botão (menos atrito, mais risco de erro de
interpretação).

### Backend — novo módulo `backend/src/whatsapp/`

| Arquivo | Responsabilidade |
|---|---|
| `whatsapp-webhook.controller.ts` | `GET /whatsapp/webhook` (desafio `hub.verify_token`) e `POST /whatsapp/webhook` (mensagens). **Sem** `FirebaseAuthGuard`; valida `X-Hub-Signature-256` com `WHATSAPP_APP_SECRET` sobre o corpo cru. Responde 200 rápido e processa de forma assíncrona |
| `whatsapp-vinculo.controller.ts` | `POST /whatsapp/vinculo` (gera código), `GET /whatsapp/vinculo`, `DELETE /whatsapp/vinculo` — com `FirebaseAuthGuard` + `@RequerRecurso('whatsapp_lancamento')` |
| `whatsapp-api-client.service.ts` | Envio de texto e *reply buttons* via Graph API |
| `whatsapp-message-parser.service.ts` | Regex → fallback LLM → `LancamentoProposto` |
| `whatsapp-conversa.service.ts` | Máquina de estados curta: vínculo, proposta, confirmação, perguntas de complemento, comandos |

Reuso: cria o lançamento via `LancamentosService` (nada de Prisma direto), então
confirmação, agenda e Saldo Livre continuam num lugar só.

### Modelo de dados

```prisma
enum OrigemLancamento {
  EMAIL_PARSER
  MANUAL
  WHATSAPP        // novo
}

model WhatsappVinculo {
  id                    String    @id @default(uuid())
  userId                String    @unique @map("user_id")
  telefoneHash          String    @unique @map("telefone_hash")          // HMAC-SHA256 do E.164, para lookup
  telefoneCriptografado String    @map("telefone_criptografado")        // via módulo crypto existente
  verificadoEm          DateTime? @map("verificado_em")
  codigoVinculo         String?   @map("codigo_vinculo")
  codigoExpiraEm        DateTime? @map("codigo_expira_em")
  ativo                 Boolean   @default(true)
  criadoEm              DateTime  @default(now()) @map("criado_em")

  @@map("whatsapp_vinculos")
}

model WhatsappMensagem {
  wamid        String   @id                       // id da Meta → idempotência (a Meta reenvia webhooks)
  userId       String?  @map("user_id")
  estado       String                             // 'PROPOSTO' | 'CONFIRMADO' | 'DESCARTADO' | 'AGUARDANDO_VALOR' | 'IGNORADO'
  lancamentoId String?  @map("lancamento_id")
  criadoEm     DateTime @default(now()) @map("criado_em")

  @@index([userId, criadoEm])
  @@map("whatsapp_mensagens")
}
```

**O texto da mensagem não é guardado** (mesma linha de minimização da decisão
de corpo de e-mail em `2026-09-12-financas-assistidas-design.md`): extrai,
cria o lançamento e descarta.

### Regras de plano no WhatsApp

- Mensagem de um número vinculado cujo usuário **não é mais Premium** → uma
  resposta gentil ("O lançamento pelo WhatsApp faz parte do Premium. Seus
  lançamentos anteriores continuam no app.") e nada é criado. Máximo de uma
  resposta dessas por dia por número.
- Número desconhecido → resposta única explicando como vincular pelo app.
- Cota de uso justo no Premium (ex.: 300 lançamentos/mês) só como proteção
  contra abuso; `UsoMensal` com `recurso = 'whatsapp_lancamento'`.

### Segurança e LGPD

- Validação de assinatura HMAC em todo POST do webhook; rejeita sem assinatura.
- Idempotência por `wamid`.
- Limite de taxa por número (ex.: 30 msgs/min) para conter loops e abuso.
- Telefone criptografado em repouso; busca só pelo hash.
- Consentimento explícito na tela de vínculo (o que é lido, o que é guardado,
  como desvincular).
- `parar` pelo WhatsApp ou "Desvincular" no app apagam o vínculo na hora.
- Texto da mensagem não vai para logs nem para o Sentry (scrub no `beforeSend`).

### Infra

- Webhook público: `https://<dominio-duckdns>/api/whatsapp/webhook` pelo Caddy
  já existente no OCI (TLS ok).
- Novas variáveis em `backend/.env.example` (sem valores):
  `WHATSAPP_PHONE_NUMBER_ID`, `WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_APP_SECRET`,
  `WHATSAPP_VERIFY_TOKEN`, `WHATSAPP_NUMERO_PUBLICO`, `REVENUECAT_WEBHOOK_SECRET`.
- `NestFactory.create(AppModule, { rawBody: true })` para validar a assinatura.

---

## Fases de entrega (proposta)

| Fase | Entrega | Depende de |
|---|---|---|
| **F0 — Fundação de planos** | enum `Plano`, `Assinatura`, `UsoMensal`, `EntitlementsService`, guard, `GET /users/me/plano`, concessão manual por admin, gates nos pontos listados, `planoProvider` + selos "Premium" no mobile | — |
| **F1 — Cobrança** | RevenueCat + produtos nas lojas + webhook + telas "Conheça o Premium" / "Meu plano" + teste de 14 dias | F0, contas de desenvolvedor Play/Apple |
| **F2 — WhatsApp MVP** | vínculo, webhook, parser regex + fallback Haiku, confirmação por botão, `resumo`/`desfazer`/`ajuda`/`parar` | F0 (F1 não é obrigatória — dá para testar com concessão manual) |
| **F3 — WhatsApp+** (futuro) | áudio (transcrição), foto de cupom/boleto, lembretes de vencimento via template pago, consulta "quanto gastei com mercado?" | F2 |

F0 e F2 podem andar em paralelo com a verificação da conta Meta Business, que
costuma ser o gargalo de calendário.

## Testes

- `EntitlementsService`: matriz recurso × plano, cota estourando, virada de mês,
  admin sempre Premium, concessão expirada.
- `EntitlementsGuard`: 402 com corpo correto.
- Webhook RevenueCat: cada evento (compra, renovação, cancelamento, expiração,
  reembolso, carência) → estado final de `Assinatura`/`User.plano`.
- WhatsApp: assinatura inválida → 401; `wamid` repetido → processado uma vez;
  vínculo com código válido/expirado/errado; usuário rebaixado; número desconhecido.
- Parser: fixtures de frases reais em `whatsapp/parser/__fixtures__/` (valores
  com vírgula/ponto, "R$", "45 reais", datas relativas, nomes de conta com erro
  de digitação), no padrão dos fixtures de e-mail em `financas/parser/`.
- Mobile: `RecursoPremium` nos dois estados, interceptor 402, telas de plano.

## Fora de escopo

- Planos familiares/compartilhados e B2B (empresas/terapeutas).
- Pagamento na web (Stripe), Pix ou boleto.
- Mensagens proativas por WhatsApp (templates pagos).
- WhatsApp para outros pilares (agenda, e-mail, emergência continua via `wa.me`).
- Cupons, indicações e preços regionais.

## Perguntas em aberto para validação

1. **Separação:** fica com a opção (A), (B) ou (C) da seção de e-mail/agenda? Os
   limites do Free (2 contas, 1 cartão, 5 rascunhos/mês) fazem sentido?
2. **Biofeedback** 100% Free, como proposto, ou algo (ex.: histórico longo,
   exportação) vira Premium?
3. **WhatsApp no Free:** exclusivo do Premium ou uma degustação (ex.: 10
   lançamentos/mês)?
4. **Confirmação no WhatsApp:** botão "Confirmar" obrigatório (proposta) ou
   lança direto como confirmado?
5. **Cobrança:** RevenueCat ou integração direta com as lojas? Preço e duração
   do teste grátis?
6. **Usuários atuais / testadores:** ganham Premium por concessão manual por um
   tempo (ex.: 6 meses)?
7. **Número do WhatsApp:** já existe um número/conta Meta Business para o Sincro,
   ou precisamos criar?
