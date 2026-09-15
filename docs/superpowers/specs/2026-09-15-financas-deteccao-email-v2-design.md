# Finanças — detecção de e-mails financeiros v2 (recall real, reprocessamento, PDF anexo)

## Contexto e objetivo

A fase "Finanças Assistidas" (spec de 2026-09-12) plugou o
`EmailFinanceRegexParserService` no `EmailSyncService` para transformar e-mails de
fatura/boleto em `LancamentoFinanceiro` em `PENDENTE_REVISAO`. Na prática, o usuário
vê e-mails de "fatura fechada" na caixa do app e **nenhum** lançamento em Finanças.

Investigação de 2026-09-15 (24 remetentes/assuntos reais dos últimos 60 dias rodados
pelo código de produção; evidência em `probe-*.ts`, reproduzível) encontrou quatro
bloqueios em cascata:

| # | Bloqueio | Onde | Efeito medido |
|---|----------|------|---------------|
| 0 | Pré-filtro `alreadySynced` roda antes do parser; o loop de sync existe desde 02/08, o parser só desde 12/09 | `email-sync.service.ts:50-53` vs `:67` | Todo e-mail sincronizado antes de 12/09 nunca chega ao parser e nunca será reprocessado |
| 1 | `matches()` exige domínio numa lista de 8 OU "fatura"+"cartão" no assunto | `email-finance-regex-parser.service.ts` `INSTITUTION_MAP`, `isCardInvoiceSubject` | 6 de 12 e-mails financeiros reais descartados (Santander, Pefisa, Neoenergia, Starlink, Porto); 6 falsos positivos (extratos/marketing Nubank) |
| 2 | `parse()` exige sinal "ancorado" (valor com `R$`, data com ano ou código de barras) para emissor que entra por assunto | guard `:143-145` | "A fatura do seu cartão Nubank está fechada" → `null` (valor só no PDF anexo; "vence no dia 15 de setembro" sem ano) |
| 3 | Fallback de "próxima linha" em `extractValor` pega a primeira moeda que encontrar | `extractValor` `:288-292` | Leroy/Pefisa 15/09: fatura de R$ 520,61 vira lançamento de **R$ 86,33** (parcela 12×) com vencimento errado |

**Objetivo:** capturar 100 % dos e-mails financeiros reais da amostra (12/12) com zero
falso positivo na mesma amostra, sem fabricar valor/data, reprocessando o que já foi
sincronizado, e extraindo valor/vencimento do PDF anexo quando o corpo não os traz —
mantendo a decisão da spec anterior: **100 % determinístico, sem LLM**.

## Decisões (via brainstorming com o usuário, 2026-09-15)

1. **Abordagem:** regex endurecido + reprocessamento + leitura do PDF anexo. LLM segue
   fora (spec de 12/09); registrado como fase futura.
2. **Marcador Gmail do usuário como sinal:** e-mail com o marcador `Sincro/Finanças`
   (nome fixo nesta fase) é candidato mesmo que nenhuma outra regra case.
3. **Reprocessamento é contínuo, não script único:** cada `EmailSummary` guarda a
   versão do parser que o avaliou; o sync reprocessa quem está atrasado. Quando as
   regras mudarem de novo, basta subir a constante.
4. **Lançamentos criados pelo parser e ainda `PENDENTE_REVISAO` pertencem à máquina:**
   o reprocessamento pode corrigi-los ou removê-los. `CONFIRMADO`/`IGNORADO` são do
   usuário e nunca são tocados.
5. **Prefere-se lançamento com `valor: null` a lançamento nenhum** para emissor
   confiável ou assunto de ciclo de fatura — a revisão pelo usuário existe para isso.
   Prefere-se `valor: null` a valor fabricado, sempre.
6. **Sem mudança no mobile** nesta fase: a aba "Pendentes de revisão" já mostra o que
   o backend criar.

## Fora de escopo

- Ampliar a janela da primeira sincronização (`is:unread`, 7 dias, 50 msgs) — e-mails
  anteriores ao primeiro sync (Pefisa 24/07, Neoenergia 22/07) continuam fora.
  Candidato a fase 2: "varredura financeira inicial" de 60 dias.
- Paginação do `history.list` (lotes > 100 eventos entre ciclos) — risco latente
  separado, registrado.
- PDF protegido por senha (Santander usa CPF): tentativa falha em silêncio → `valor: null`.
- Nome do marcador configurável pelo usuário no app.
- Qualquer uso de LLM.

## Arquitetura e fluxo de dados

```
EmailSyncService.syncUser(userId)
  │
  ├─ (A) NOVOS e-mails (como hoje) ─────────────────────────────────────────────
  │    fetchNewEmails → FetchedEmail agora carrega labelIds
  │    para cada e-mail sem emailSummary:
  │      classifier.classify(...)                         (inalterado)
  │      resultado = FinanceEmailProcessor.processar(userId, email)   ← NOVO ponto único
  │      emailSummary.create({ ..., parserFinancasVersao: FINANCE_PARSER_VERSION })
  │
  └─ (B) REPROCESSAMENTO ───────────────────────────────────────────────────────
       summaries = emailSummary.findMany({ userId,
                     OR: [{parserFinancasVersao: null}, {parserFinancasVersao: {lt: FINANCE_PARSER_VERSION}}],
                     orderBy: recebidoEm desc, take: 50 })
       para cada: FinanceEmailProcessor.processar(userId, summary→email)
                  emailSummary.update({ parserFinancasVersao: FINANCE_PARSER_VERSION })

FinanceEmailProcessor.processar(userId, email{gmailMessageId, remetente, assunto, recebidoEm, labelIds?})
  1. detector.matches(remetente, assunto, { temMarcadorFinancas })   → não casa: garante que
     não há lançamento EMAIL_PARSER+PENDENTE_REVISAO órfão para esse e-mail (remove se houver); fim
  2. corpo = gmailApiClient.fetchFullBody(...)  (agora SEMPRE passa por htmlParaTextoLegivel
     quando o text/plain contém HTML — ver "Corpo")
  3. parsed = parser.parse({ remetente, assunto, corpo, recebidoEm })
  4. se parsed.valor === null || !parsed.dataEncontrada:
        textoPdf = gmailApiClient.fetchPdfAttachmentText(...)  (1 PDF, ≤ 5 MB, falha → null)
        parsed = parser.complementarComTexto(parsed, textoPdf)
  5. upsert do LancamentoFinanceiro por (userId, emailMessageId):
        não existe → create PENDENTE_REVISAO / EMAIL_PARSER
        existe EMAIL_PARSER + PENDENTE_REVISAO → update campos extraídos
        existe CONFIRMADO/IGNORADO/MANUAL → não toca
```

Toda a lógica financeira sai do corpo do loop de sync para `FinanceEmailProcessor`
(novo, em `src/financas/parser/`), para que (A) e (B) usem exatamente o mesmo caminho e
o `EmailSyncService` volte a só orquestrar.

## Modelagem de dados (Prisma)

```prisma
model EmailSummary {
  ...
  labelIds             String[] @default([]) @map("label_ids")          // NOVO: para o marcador no reprocessamento
  parserFinancasVersao Int?     @map("parser_financas_versao")          // NOVO: null = nunca avaliado
  @@index([userId, parserFinancasVersao])
}
```

Migration `add_email_finance_parser_version`: duas colunas + índice; sem backfill de dados
(null é exatamente o estado "precisa reprocessar"). `LancamentoFinanceiro` não muda.

## Corpo do e-mail

`GmailApiClient.fetchFullBody` hoje devolve a parte `text/plain` crua quando ela existe.
Remetentes reais (Pefisa/Leroy) entregam HTML dentro de `text/plain`; o parser então vê
tags e `<br>` na mesma linha, o que alimenta o bloqueio 3. Regra nova: se o texto plano
parecer HTML (`/^\s*(<!doctype|<html|<table|<div)/i` nos primeiros 200 chars), passa por
`htmlParaTextoLegivel` também. Vale para o leitor de e-mail do app (melhoria colateral).

## Detecção — `matches(remetente, assunto, { temMarcadorFinancas })`

Determinística, em três camadas. Tudo NFC-normalizado e case-insensitive.

**1. Vetos (qualquer um → `false`, exceto se `temMarcadorFinancas`):**
- `isSettledPaymentSubject(assunto)` (existente).
- Assunto: `\bextrato\b`, `d[eé]bito autom[aá]tico .{0,30}(conclu[ií]d|cadastrad)`,
  `recibo de pedido`, `pedido .{0,20}faturado`, `seu pedido`.
- Remetente: subdomínio/local-part de marketing — `novidades\.|news@|newsletter|marketing@|promo`.

**2. Sinais positivos (qualquer um → `true`):**
- (a) Domínio em `INSTITUTION_MAP` (ampliado, ver abaixo).
- (b) Assunto com substantivo de cobrança:
  `\bfaturas?\b`, `\bboletos?\b`, `\bcobran[çc]a\b`, `\bvenc(e|imento)\b`,
  `\bcons[óo]rcio\b`, `\bmensalidade\b`, `conta de (luz|energia|[áa]gua|g[áa]s|internet)`,
  `\bparcela\b`.
- (c) Local-part do remetente financeira:
  `^(fatura|faturamento|cobranca|cobrança|boleto|pagamento|financeiro|billing|invoice|consorcio|portoconsorcio)`.
- (d) `temMarcadorFinancas === true`.

**3. `INSTITUTION_MAP` ampliado** (domínio → nome, `tipoPadrao`):
Nubank (`nubank.com.br`, exclui `novidades.`), Itaú (`itau.com.br`, `itaucard.com.br`),
Inter, Bradesco, C6, Santander (`santander.com.br`), Pefisa/Celebre (`pefisa.com.br`,
`leroymerlinpay.pefisa.com.br`), Sam's Club (`cartaosamsclub.com.br`) — todos `CARTAO`;
Claro, Vivo, TIM, Enel, Neoenergia (`neoenergiabrasilia.com.br`,
`faturaneoenergiabrasilia.com.br`), Starlink (`starlink.com`), Porto Seguro
(`portoseguro.com.br`, `OUTRO`) — `OUTRO`.

Alvo medido na amostra real de 24 (fixture `amostra-real-2026-09.json`): 12/12
financeiros capturados, 0/12 ruídos capturados. O teste falha se qualquer linha da
amostra mudar de lado.

## Extração — `parse()` e `complementarComTexto()`

**Tipo (`FATURA_CARTAO` vs `DESPESA`)**
- `tipoPadrao === 'OUTRO'` → sempre `DESPESA` (inalterado).
- `FATURA_CARTAO` se: `isCardInvoiceSubject(assunto)` OU (`tipoPadrao === 'CARTAO'` e
  `FATURA_LIFECYCLE_RE`) OU **novo:** `cart(ão|ao)` nos primeiros 600 chars do corpo a
  ≤ 40 chars de `fatura` ("A fatura mensal do seu cartão SANTANDER…"). O limite de 600
  chars evita rodapés promocionais.
- Caso contrário `DESPESA`.

**Guard substituído.** Sai o `return null` por falta de sinal ancorado. Entra:
- Se `matches()` casou por (a), (c) ou (d) → cria (valor pode ser `null`).
- Se casou **só** por (b) (assunto) → cria se houver ao menos um de: valor ancorado,
  data ancorada, código de barras, `FATURA_LIFECYCLE_RE` no assunto (ampliada com
  `chegou` e `vence em breve`, além de `fechou/fechada/disponível/gerada/emitida`). Senão `null` (mantém a proteção contra
  "Parcele sua fatura em 12x" de remetente desconhecido).

**Valor**
- Âncoras ampliadas: + `no valor de`, `valor:`, `total:`, `valor da conta`,
  `valor do boleto`, `total da conta`.
- Moeda com `R$` opcional **quando ancorada**: `(?:R\$\s*)?((?:\d{1,3}(?:\.\d{3})*|\d+),\d{2})`.
  Sem âncora continua exigindo `R$` (fallback de valor único, inalterado).
- Linhas de parcelamento nunca fornecem valor: qualquer linha com
  `\d+\s*(x|vezes)\s+de`, `parcelas?\s+de`, `m[ií]nimo`, `ap[óo]s o vencimento` é ignorada
  tanto na linha da âncora quanto no fallback de próxima linha.
- Fallback de próxima linha só quando a próxima linha **não** é uma linha de parcelamento
  e **não** contém outra âncora.

**Data de vencimento**
- Âncoras: + `vence no dia`, `vencimento:`, `vence em`, `data de vencimento`.
- Novos formatos, ambos com inferência de ano: `dd/mm` sem ano e `dd de <mês>` sem ano.
  Ano inferido = ano de `recebidoEm`; se a data resultante for anterior a
  `recebidoEm − 15 dias`, soma 1 ano (fatura recebida em 28/12 que vence "10/01").
- `parse()` passa a devolver `dataEncontrada: boolean` (já existe internamente como
  `encontradaNoCorpo`; vira parte de `ParsedLancamento`) para o processador decidir se
  consulta o PDF.

**PDF anexo — `GmailApiClient.fetchPdfAttachmentText(refreshToken, messageId)`**
- `messages.get(format: 'full')` → primeira parte com `mimeType === 'application/pdf'`
  ou `filename` terminando em `.pdf` (Santander manda `application/octet-stream`),
  `body.size ≤ 5 MB`.
- `attachments.get` → `pdf-parse` (mesmo padrão de `rag/document-processor.service.ts`),
  limitado às 3 primeiras páginas. Qualquer erro (senha, PDF corrompido, timeout) →
  `null`, log em `debug`.
- `parser.complementarComTexto(parsed, textoPdf)`: preenche **apenas** os campos ainda
  `null`/não encontrados usando as mesmas âncoras; nunca sobrescreve o que o corpo deu.

## Reprocessamento e escrita idempotente

- `FINANCE_PARSER_VERSION = 2` (constante exportada pelo parser). Versão 1 = regras
  anteriores (nunca gravada; `null` cobre o legado).
- Passo (B) roda a cada `syncUser`, **depois** dos novos, `take: 50` por usuário por ciclo,
  do mais recente para o mais antigo. Com cron de 20 min, 500 summaries são zerados em
  ~3 h. O carimbo é gravado **sempre**, mesmo em erro (logado em `error`), para um e-mail
  problemático não bloquear a fila; a próxima subida de versão o revisita.
- Escrita por `(userId, emailMessageId)`:
  - sem lançamento → `create`;
  - `EMAIL_PARSER` + `PENDENTE_REVISAO` → `update` de `tipo, descricao, instituicao, valor,
    dataVencimento, dataCompetencia, codigoBarras`;
  - `EMAIL_PARSER` + `PENDENTE_REVISAO` e `matches()` agora **falso** → `delete` (era falso
    positivo das regras antigas, ex.: "Extrato da sua conta do Nubank");
  - `CONFIRMADO`, `IGNORADO` ou `origem MANUAL` → não toca.
- P2002 continua tratado como corrida benigna.

## Marcador Gmail

- Nome fixo `Sincro/Finanças`. Uma vez por `syncUser`, `users.labels.list` resolve o
  `labelId` (cache em memória por conexão durante o ciclo). Se o marcador não existir,
  sinal (d) fica desligado — sem erro.
- `FetchedEmail.labelIds` passa a ser preenchido por `fetchMessages` (já lê `labelIds`
  para o filtro de ruído) e persistido em `EmailSummary.labelIds` para o reprocessamento.

## Estratégia de testes

**Unitários — parser (`email-finance-regex-parser.service.spec.ts`)**
- Tabela real de 24 (`__fixtures__/amostra-real-2026-09.json`, remetente + assunto +
  `financeiro: boolean`): asserção de 12/12 e 0/12.
- Fixtures de corpo reais (texto já convertido, dados pessoais mascarados):
  - `nubank-fatura-fechada.txt` → `FATURA_CARTAO`, `valor: null`, `dataVencimento: 2026-09-15`
    (inferida de "15 de setembro" + recebido em 08/09/2026).
  - `santander-fatura-por-email.txt` → `FATURA_CARTAO` (cartão no corpo), `valor: 111.46`
    ("no valor de"), `dataVencimento: 2026-08-10`.
  - `leroy-pefisa-celebre.txt` e variante minificada (`<br>` sem quebra) → `FATURA_CARTAO`,
    `valor: 520.61`, `dataVencimento: 2026-09-17`; **nunca** 86.33.
  - `sams-vence-em-breve.txt` → cria com o que houver; `valor` nunca vem de "R$ X em Nx".
  - Regressão: "Parcele sua fatura em 12x" de remetente desconhecido → `null`;
    "Extrato da fatura do Cartão Nubank" → `matches() === false`.
- Data sem ano: "10/01" recebido em 28/12/2026 → 2027-01-10; "15 de setembro" recebido em
  08/09/2026 → 2026-09-15.
- `complementarComTexto`: preenche só `null`; não sobrescreve.

**Unitários — `FinanceEmailProcessor`** (Prisma e Gmail mockados): create / update de
pendente / delete de falso positivo / não toca confirmado / PDF consultado só quando falta
valor ou data / erro de PDF → segue com `null`.

**Unitários — `EmailSyncService`**: novos e-mails carimbam versão; passo (B) pega
`null` e `< versão`, respeita `take: 50`, carimba mesmo em erro; marcador resolve labelId
uma vez por ciclo; ausência do marcador não quebra.

**Unitários — `GmailApiClient`**: `fetchFullBody` converte `text/plain` que é HTML;
`fetchPdfAttachmentText` escolhe a parte certa por mimeType **ou** extensão, respeita 5 MB,
devolve `null` em PDF protegido (fixture gerada com senha).

**Verificação em produção (manual, após deploy):**
```sql
select gmail_message_id, assunto, parser_financas_versao from resumos_email
 where gmail_message_id in ('19fceaf2b80763e0','1a07f4e5e9882fe6','1a0a4f412c11e93b');
select descricao, tipo, valor, data_vencimento, status from lancamentos_financeiros
 where origem = 'EMAIL_PARSER' order by criado_em desc limit 20;
```
Esperado: os três com versão 2; Nubank 08/09 (`valor null`, venc. 15/09), Santander
(`111.46`, 10/08), Leroy (`520.61`, 17/09) em `PENDENTE_REVISAO`; nenhum "Extrato".

## Critérios de sucesso

- Amostra real: 12/12 capturados, 0/12 ruídos, sem valor fabricado (teste automatizado).
- Após um ciclo completo de reprocessamento na VPS, os e-mails de fatura já visíveis no
  app aparecem em "Pendentes de revisão".
- `flutter`/mobile inalterado; `npm test` do backend verde; `prisma migrate` aplicada.
- Nenhuma chamada a LLM no caminho de finanças.
