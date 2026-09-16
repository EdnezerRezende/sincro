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

**Objetivo:** reconhecer e-mail de cobrança de **qualquer** instituição financeira (não só as
listadas), capturando 100 % dos e-mails financeiros reais da amostra (12/12) com zero
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
6. **Abrangência sobre allowlist (2026-09-15, segunda rodada):** a detecção reconhece
   qualquer instituição por sinais genéricos; `INSTITUTION_MAP` é só enriquecimento e o teste
   com instituições fictícias prova que ela não é necessária.
7. **Sem mudança no mobile** nesta fase: a aba "Pendentes de revisão" já mostra o que
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
  ├─ (0) marcador: labelId = labels.list().find(name === 'Sincro/Finanças')            ← 1 chamada/ciclo
  │      ids = labelId ? messages.list({ labelIds: [labelId], q: 'newer_than:90d', maxResults: 100 }) : ∅
  │      re-enfileira ($executeRaw): UPDATE resumos_email SET parser_financas_versao = NULL
  │        WHERE user_id = $1 AND gmail_message_id = ANY($2) AND NOT (label_ids @> ARRAY[$labelId])
  │        — só quem ainda NÃO tinha o marcador persistido; o processamento grava label_ids ∪ {labelId}
  │      (falha transitória aqui → log warn, ids = ∅, indisponivel = true; ciclo continua, mas (A)
  │        carimba parserFinancasVersao = null nos e-mails novos deste ciclo — mesmo com processar()
  │        já rodando — e (B) é pulado inteiro: rodar (B) com o Set vazio faria um e-mail rotulado
  │        pelo usuário perder o marcador para sempre, já que o Gmail já devolve o label em
  │        email.labelIds e "NOT (label_ids @> ARRAY[...])" nunca mais o re-enfileiraria)
  │
  ├─ (A) NOVOS e-mails (como hoje)
  │    fetchNewEmails → FetchedEmail carrega labelIds
  │    para cada e-mail sem emailSummary:
  │      classifier.classify(...)                                   (inalterado)
  │      resultado = FinanceEmailProcessor.processar(userId, email, { marcado: ids.has(id) })
  │      emailSummary.create({ ..., labelIds,
  │        parserFinancasVersao: resultado.transitorio ? null : FINANCE_PARSER_VERSION,
  │        parserFinancasTentativas: resultado.transitorio ? 1 : 0 })                    ← falha transitória fica p/ (B)
  │
  └─ (B) REPROCESSAMENTO
       summaries = emailSummary.findMany({ userId,
                     OR: [{parserFinancasVersao: null}, {parserFinancasVersao: {lt: FINANCE_PARSER_VERSION}}],
                     orderBy: [{parserFinancasTentativas: 'asc'}, {recebidoEm: 'desc'}], take: 50 })
       para cada: FinanceEmailProcessor.processar(userId, summary→email, { marcado: ids.has(gmailMessageId) })
                  sucesso ou erro permanente → update({ parserFinancasVersao: V, parserFinancasTentativas: 0 })
                  transitório-conta → tentativas += 1; NÃO carimba; interrompe o lote
                  transitório-mensagem (5xx) → tentativas += 1; NÃO carimba; segue
       fila ordenada por tentativas asc, recebidoEm desc (venenosa afunda, nunca se perde)

FinanceEmailProcessor.processar(userId, email, { marcado })
  1. triagem = detector.triagem(remetente, assunto, { marcado })
     'nao' → removerLancamentoDaMaquina(userId, gmailMessageId); fim            (sem chamada de corpo)
  2. { texto, anexos } = gmailApiClient.fetchFullBodyComAnexos(refreshToken, gmailMessageId)
     — 1 chamada messages.get(format:'full'); devolve texto legível (ver "Corpo") e metadados
       dos anexos [{ filename, mimeType, size, attachmentId }] (sem baixar)
  3. parsed = parser.parse({ remetente, assunto, corpo: texto, recebidoEm, triagem, anexos })
     null → removerLancamentoDaMaquina(...); fim
  4. se parsed.valor === null || !parsed.dataEncontrada:
        pdf = anexos.find(PDF ≤ 5 MB) → attachments.get (1 chamada) → pdf-parse (3 páginas) → texto | null
        parsed = parser.complementarComTexto(parsed, textoPdf)
  5. gravar por (userId, emailMessageId):
        não existe → create PENDENTE_REVISAO / EMAIL_PARSER
        existe EMAIL_PARSER + PENDENTE_REVISAO → updateMany({ where: {userId, emailMessageId, origem, status}, data })
        existe CONFIRMADO/IGNORADO/MANUAL → não toca

removerLancamentoDaMaquina = deleteMany({ userId, emailMessageId, origem: 'EMAIL_PARSER', status: 'PENDENTE_REVISAO' })
```

Custo por e-mail: 0 chamadas extras para `'nao'`; 1 (`messages.get full`) para candidato; 2 se
precisar do PDF. `processar` devolve `{ transitorio: boolean }` para o chamador decidir o carimbo. Toda a lógica financeira sai do loop de sync para `FinanceEmailProcessor`
(novo, em `src/financas/parser/`), para que (A) e (B) usem exatamente o mesmo caminho.
`matches()` deixa de existir como API pública; `triagem() !== 'nao'` é o equivalente.

## Modelagem de dados (Prisma)

```prisma
model EmailSummary {
  ...
  labelIds             String[] @default([]) @map("label_ids")
  parserFinancasVersao    Int?  @map("parser_financas_versao")     // null = nunca avaliado
  parserFinancasTentativas Int  @default(0) @map("parser_financas_tentativas") // falhas transitórias seguidas
  @@index([userId, parserFinancasVersao, parserFinancasTentativas])
}
```

Migration `add_email_finance_parser_version`: três colunas + índice `[userId, parserFinancasVersao, parserFinancasTentativas]`; sem backfill (null é
exatamente o estado "precisa reprocessar"). `LancamentoFinanceiro` não muda.

## Corpo do e-mail

`GmailApiClient.fetchFullBody` hoje devolve a parte `text/plain` crua quando existe. Remetentes
reais (Pefisa/Leroy) entregam HTML dentro de `text/plain`. Regra nova, em
`fetchFullBodyComAnexos` (que substitui `fetchFullBody` para os **três** consumidores —
`email-summary.controller.ts`, `email-reply.controller.ts` e o parser): se os **primeiros 340
caracteres** do texto plano (após `trimStart()` — que já remove um BOM inicial sozinho, U+FEFF é
`WhiteSpace` pela spec ECMA-262, sem precisar de `.replace()` separado) casam com

```
/<!doctype\s|<!--|<(html|head|body|table|div|p|center|br|span|font)(?:\s*\/?>|\s+[\w:.-]+(?:\s+[\w:.-]+)*\s*=)/i
```

o texto passa por `htmlParaTextoLegivel`. A janela é 340 chars, não 300: uma tag que começa perto
do limite de 300 (preheader longo antes do doctype/`<html>`) precisa de espaço depois do `<` para
o nome da tag, o(s) atributo(s) e o fechamento — cortar em 300 partiria a tag ao meio e perderia a
detecção. O regex tem três alternativas: (1) `<!doctype\s` cobre o doctype legado do Word/Outlook
(`<!DOCTYPE HTML PUBLIC "-//W3C//DTD ...">`), cujo conteúdo não é `nome=valor` e por isso é tratado
à parte da regra de atributos; (2) `<!--` cobre comentários, incluindo condicionais do Outlook
(`<!--[if mso]>`) e preheaders, sem exigir espaço depois dos hífens; (3) uma tag conhecida seguida
de fechamento imediato (`<br>`, `<br/>`) OU de uma lista de um ou mais atributos (nomes com
letra/dígito/`_`/`:`/`.`/`-` — `:` e `.` cobrem `xmlns:v=`) terminando em `=`. A lista de atributos
só termina em `=`, nunca direto em `>`: é isso que mantém "Se x<p então y > z" como falso positivo
evitado (senão "y > z", com espaço antes do `>`, colaria como fechamento de uma tag `<p ...>`), e
ainda cobre atributo booleano antes de outro com valor, como em `<table border cellpadding=0>`
("border" sem valor, só "cellpadding=" precisa fechar em `=`). Também evita falso positivo em
prosa genuína como "O preço <p 10 reais", "De: Paulo <p@empresa.com>" ou "<br@empresa.com.br>", que
a versão anterior (ancorada só em `\b`) detectava incorretamente como HTML. Preheader de texto
antes de `<html>` é coberto porque a busca não é ancorada no início. Texto plano genuíno (sem tag
real nos 340 primeiros chars) **não** passa pela conversão. Quando não há `text/plain` utilizável,
cai para a parte `text/html` (também via `htmlParaTextoLegivel`) — mas só se essa conversão gerar
texto não-vazio; senão, cai no `snippet` com `ehPreview: true`, como antes. Melhoria colateral para
o leitor de e-mail do app; sem mudança de contrato para ele (`{ texto, ehPreview }` continua;
`anexos` é campo adicional, coletado recursivamente pela árvore MIME inteira sem baixar conteúdo).

## Detecção — genérica para qualquer instituição

**Princípio (decisão do usuário, 2026-09-15):** reconhecer e-mail de cobrança de **qualquer**
instituição financeira, incluindo as nunca vistas. Nenhuma regra de criação depende de o
remetente estar numa lista. `INSTITUTION_MAP` vira **enriquecimento** (nome de exibição e
`tipoPadrao` quando conhecido).

**Convenção de regex desta spec:** onde está escrito `\b`, a implementação usa fronteira de
palavra **Unicode** — `(?<![\p{L}\p{N}])…(?![\p{L}\p{N}])` com flag `u`, via helper `wb()`
(mesma técnica de `containsWholeWord` no classificador). O `\b` nativo do JS é ASCII e falha
em `carnê`, `venc.`, `até`. Texto sempre NFC-normalizado e case-insensitive.
**Remetente:** S3 e S7 operam sobre o **endereço extraído** (`extractEmailAddress`, já existe),
nunca sobre o header `From` cru (`'Pefisa <pagamento@pefisa.com.br>'` é o formato real).

Duas etapas, porque o corpo só é buscado para candidatos:

```
triagem(remetente, assunto, { marcado })  →  'nao' | 'forte' | 'fraco'
parse(candidato + corpo + anexos)          →  ParsedLancamento | null
```

### Etapa 1 — triagem (remetente + assunto + marcador; sem corpo)

Ordem de avaliação: marcador → vetos duros → S1a → vetos brandos → demais fortes (S1b/S2/S3/S8) →
vetos brandos tardios → fracos. Constantes:
`CABECA_TIPO = 600` chars (decisão de tipo), `CABECA_EVIDENCIA = 1500` chars (evidência da etapa 2).

**S4 — marcador `Sincro/Finanças`** (`marcado === true`) → `'forte'`, ignorando vetos e a
evidência negativa da etapa 2. O usuário decidiu.

**Vetos duros** (→ `'nao'`, sempre):
- `isSettledPaymentSubject(assunto)` — pagamento já feito ("Comprovante de pagamento da fatura").
- Assunto: `\bextratos?\b` · `d[eé]bito autom[aá]tico .{0,30}(conclu[ií]d|cadastrad|ativad)` ·
  `recibo de pedido` · `pedido .{0,20}(faturado|enviado|entregue)` · `\bseu pedido\b` ·
  `\bpesquisa\b` · `\bconvite\b` · `\bganhe\b` · `\bsorteio\b` · `\bcashback\b` ·
  `\d+ ?% ?(off|de desconto)` · `\bsem juros\b` · `\bsimule\b` · `pr[ée]-aprovad` ·
  `\bcontestad|contesta[çc][ãa]o|em an[áa]lise|\bdisputa\b` · `\bcomo (funciona|aderir|receber)\b` ·
  `cadastre-se` · `\bprefira\b` · `\bagora voc[êe] pode\b` · `\bsenha\b` ·
  `\bc[óo]digo de (verifica[çc][ãa]o|seguran[çc]a|acesso)\b` · `\balerta de seguran[çc]a\b` ·
  `\brenove\b` · `\bcupom\b` · `\bofertas?\b` · `promo[çc][ãa]o` ·
  `\bagendad[oa]\b` · `\bestorno\b` · `\brecebid[oa]\b` (assunto: "Pix recebido", "Pagamento recebido") ·
  `\b(receipt|paid|payment (received|successful|confirmed))\b` (assunto em inglês: "Your receipt from
  SaaS", "Payment received — thank you") · `\bparab[ée]ns\b|\bpremia[çc][ãa]o\b|\bvoc[êe] venceu\b`
  (assunto: "Você venceu! Prêmio de R$ 500,00" cai em `você venceu`; "Premiação: R$ 500,00 —
  resgate até o vencimento" cai em `premiação`; "Vencimento amanhã: R$ 89,90" não tem nenhuma das
  três formas, continua S8). `\bpr[êe]mios?\b` **não** é veto duro: em seguro, "prêmio" é o valor
  cobrado pela apólice, não um prêmio de sorteio — "Boleto do prêmio do seguro auto disponível" é
  `forte` (S2), "Prêmio do seguro: R$ 189,90 com vencimento em 10/10" é `forte` (S8), "Pagamento do
  prêmio — parcela 3/12 vence 10/10" não é `'nao'` (cai em S6 fraco). O veto só dispara quando o
  assunto tem a moldura de sorteio/prêmio de resgate (`parabéns`, `você venceu`, `premiação`), não
  a palavra `prêmio` isolada.
- Remetente (endereço): `novidades\.|^news@|newsletter|^marketing@|
  (^|[@.\-_])promo([cç]([aã]o|[oõ]es)|cional|tions?)?(?=[@.\-_])|^ofertas?@|^comunicacao@` — o
  `promo` do remetente (com ou sem as formas derivadas `promoção`/`promoções`/`promocional`/
  `promotion(s)`) é ancorado a `@`/`.`/`-`/`_` (ou início) de um lado e a `@`/`.`/`-`/`_` do outro,
  em qualquer posição do endereço — não só no início ou logo após `@` — para não pegar substring
  dentro de um domínio/local-part maior: `contato@compromovel.com.br` e
  `atendimento@promotoracredito.com.br` não são vetados (o `m` antes de `promo` em `compromovel`
  quebra a âncora à esquerda; `promotoracredito` tem `promo` seguido de `t`, que não é nenhuma das
  formas derivadas nem a âncora de fronteira à direita). São vetados: `promo@x.com`,
  `promo.x@y.com`, `x@promo.bancoz.com.br`, `promocoes@x.com`, `todomundo@promocoes.nubank.com.br`
  (o domínio inteiro é varrido, não só o local-part), `promocoes.x@y.com`,
  `x@promocional.loja.com.br`.

**Vetos brandos** (→ `'nao'` **salvo** se S1a casar — cauda de marketing num aviso legítimo não
o anula): `\bnovidades?\b` · `\bdescubra\b` · `\bconhe[çc]a\b` · `\bdica\b` · `\bsaiba\b` ·
`\bentenda\b` · `\bcomo entender\b` · `\baproveite\b`.
Positivos preservados: "Sua fatura chegou. Saiba como pagar", "Sua fatura fechou — conheça o
Nubank Ultravioleta", "Sua fatura chegou com desconto por pagamento antecipado" → `forte`.
Negativos: "Dica: como entender sua fatura", "Descubra o seu novo Cartão PJ", "Fatura digital:
saiba como aderir" (duro `como aderir`) → `'nao'`.
- Precedência: veto duro > sinal; veto brando > qualquer sinal exceto S1a.
  "Sua fatura está disponível: aproveite 20% de desconto" → `'nao'` (duro `% de desconto`).
  "Promoção: R$ 20 de desconto vence hoje" → `'nao'` (duro `promoção`, não pelo brando `de desconto`).

**Vetos brandos tardios** (→ `'nao'` **salvo** se algum sinal forte — S1a a S8 — já tiver casado;
checados depois de S8, só antes dos fracos): `\bade(rir|r[êe]ncia|s[ãa]o)\b` ·
`\b(com|de) desconto\b` **quando o assunto não tem verbo de ciclo** (ver `CICLO_RE` abaixo).
Diferente dos vetos brandos "normais" (que só deixam S1a sobreviver), este deixa **qualquer** sinal
forte sobreviver: "Taxa de adesão — boleto disponível" → `forte` (S2), porque o veto só é aplicado
depois de S2 não ter achado nada melhor. "Adesão à fatura digital" (sem nenhum sinal forte) →
`'nao'`.
- `\b(com|de) desconto\b` mora aqui, não nos brandos "normais" (checados antes de S1b/S2/S3/S8):
  se estivesse lá, "Boleto disponível com desconto até dia 5" seria vetado antes de S2 conseguir
  casar; ficando tardio, chega a S2 e dá `forte`. A regra de exceção não é mais um lookbehind
  amarrado à distância entre "disponível" e "desconto": o veto só se aplica se o assunto **não
  tiver nenhum verbo de ciclo de cobrança**, testado no assunto inteiro (não só antes de
  "desconto"), via
  `CICLO_RE = wb('\\b(fechou|fechada|chegou|dispon[ií]vel|gerada|emitida|em atraso|pendente|
  at[ée] (o )?dia \\d|' + VENC_FLEXAO + ')')` (reaproveita a mesma flexão de vencimento de S2/S8).
  Com verbo de ciclo em qualquer posição do assunto, o veto tardio não se aplica e o assunto cai
  nos sinais fracos (ou permanece `fraco`/segue adiante conforme outros sinais): "Fatura disponível
  com desconto por pagamento antecipado" → `fraco` (S6); "Fatura gerada com desconto por pagamento
  antecipado" → não `'nao'`; "Mensalidade de outubro vence dia 5 com desconto" → não `'nao'`;
  "Pague com desconto: fatura disponível" → não `'nao'` (o "disponível" está depois do "desconto",
  mas isso não importa mais — a checagem é sobre o assunto inteiro, não sobre precedência).
  Sem nenhum verbo de ciclo, o veto tardio ainda vale: "Parcele sua fatura com desconto" → `'nao'`;
  "Antecipe parcelas da sua fatura com desconto" → `'nao'`.
  "Sua fatura está disponível: aproveite 20% de desconto" continua `'nao'` pelo duro `% de
  desconto`, antes de chegar aos brandos tardios.

**Sinais fortes** (→ `'forte'`; cria lançamento mesmo sem evidência no corpo):
- S1. **Ciclo de fatura própria** (sem "conta" isolada):
  `\b(sua|a|nova)\s+(fatura|cobran[çc]a|mensalidade|boleto|carnê)\b.{0,45}\b(fechou|fechada|chegou|dispon[ií]vel|gerada|emitida|vence|venceu|em atraso|pendente)\b`
  **ou** `\bfatura\s+(por e-?mail|digital|do m[êe]s|do cart[ãa]o)\b` seguida, em até 20 chars, de
  **período ou identificador**: `[-–|:]\s*(\w+\s*/\s*\d{4}|\d{5,}|(janeiro|…|dezembro))`.
  Positivos reais: "A fatura do seu cartão Nubank está fechada" (27 chars na janela), "A fatura
  do seu Cartão de Crédito Sam's Club vence em breve" (37), "Fatura por e-mail - Setembro/2026",
  "Fatura Digital 🧾 | 3288653", "A fatura do seu Cartão Sam's Club chegou".
  Negativos: "Parcelamento da fatura agora disponível no app" (`da` ≠ `a`), "Sua conta Google
  está pendente de verificação" ("conta" fora da lista), "Fatura digital: saiba como aderir"
  (veto e sem período), "Cadastre-se na fatura por e-mail" (veto), "Fatura do mês: prefira o
  débito automático" (veto; sem período → seria fraco).
- S2. **Boleto/carnê com ciclo**: `\bboletos?\b.{0,45}\b(emitid|gerad|dispon[ií]vel|chegou|
  venc(?:e|em|eu|endo|er[áa]|id[oa]s?|imentos?)\b)` ou `\bcarnê\b.{0,45}\b(chegou|dispon[ií]vel|
  venc(?:e|em|eu|endo|er[áa]|id[oa]s?|imentos?)\b)`. A flexão de `venc` é fechada (não um prefixo
  aberto) para não pegar "vencedor" — ver nota em S8. A lista de flexões cobre `vence`, `vencem`,
  `venceu`, `vencendo`, `vencerá`, `vencido(s)`/`vencida(s)` e `vencimento(s)`.
  Positivos reais: "Novo boleto emitido no seu CPF", "Boleto vence hoje", "Seu carnê chegou",
  "Boletos vencem amanhã", "Boletos vencidos — regularize", "Boleto vencendo hoje", "Boleto
  vencerá em 3 dias".
  Negativos: "Boleto: como funciona?" (veto), "Agora você pode pagar boletos escaneando o código
  de barras" (veto `agora você pode`; sem ciclo → seria fraco), "Carne de primeira toda semana"
  (`carnê` estrito; `carne` não casa).
- S3. **Local-part inequivocamente de fatura**, no endereço extraído:
  `^(fatura|faturas|fatura_digital|faturaporemail|boleto|boletos|invoice|invoices|\w*consorcio)($|[._-])`.
  Positivos reais: `faturaporemail@santander.com.br`, `fatura_digital@cartaosamsclub.com.br`,
  `portoconsorcio@portoseguro.com.br` ("Informativo Consórcio Porto Bank" entra por aqui — é
  `forte`, e a fixture `porto-consorcio.txt` testa esse caminho). Negativos: `todomundo@`,
  `financeiro@escolax.com.br` ("Reunião de pais" — `financeiro` saiu de S3, vai a S3f).
- S8. **Valor com centavos e vencimento no assunto**: `R\$\s?(\d{1,3}(\.\d{3})*|\d+),\d{2}` **e**
  `\bvenc(?:e|em|eu|endo|er[áa]|id[oa]s?|imentos?)\b` ("Vencimento amanhã: R$ 89,90", "Parcelas
  vencem dia 10: R$ 350,00"). A flexão é fechada, não um prefixo `\bvenc` aberto — "Parabéns! Você
  é o vencedor de R$ 1.000,00" tem centavos mas `vencedor` não é nenhuma das flexões (e cai também
  no veto duro `parabéns`, antes de chegar a S8), então não é `forte`. Negativos: "Ganhe R$
  50 de bônus até o vencimento" (veto `ganhe`; sem centavos); "Seu limite subiu para R$ 5.000"
  (sem `venc`); "Promoção: R$ 20 de desconto vence hoje" (veto `promoção`; sem centavos); "Oferta:
  R$ 0 de anuidade — vence hoje" (veto `oferta`; sem centavos); "Você venceu! Prêmio de R$ 500,00"
  (veto duro `\bvocê venceu\b`, mesmo com `venceu` + centavos — `\bpr[êe]mios?\b` não é mais veto
  duro, ver seção de vetos duros).

**Sinais fracos** (→ `'fraco'`; busca corpo, cria só com evidência transacional):
- S6. Substantivo de cobrança sem ciclo: `\bfaturas?\b` · `\bboletos?\b` · `\bcarnês?\b` ·
  `\bcobran[çc]a\b` · `\bcons[óo]rcio\b` · `\bfinanciamento\b` · `\bempr[ée]stimo\b` ·
  `\bpresta[çc][ãa]o\b` · `\bvenc(e|imento)\b` · `\bmensalidade\b` · `\bparcelas?\b` ·
  `\banuidade\b` · `\bconta de (luz|energia|[áa]gua|g[áa]s|internet|telefone)\b` ·
  `\b(IPTU|IPVA|DARF|DAS)\b` (**case-sensitive** — "das suas compras" não casa) · `\bseguro\b` ·
  `\bsua conta\b.{0,25}\b(chegou|dispon[ií]vel|vence|venceu)\b` ou `\bchegou sua conta\b` ·
  `linha digit[áa]vel` · `c[óo]digo de barras` · `\bfatura\s+(por e-?mail|digital|do m[êe]s)\b` (sem período).
  A janela de "sua conta" foi alargada (era o literal `\bsua conta chegou\b`) para cobrir "Sua
  conta Vivo chegou", "Sua conta Claro está disponível" e a ordem invertida "Chegou sua conta Vivo
  de setembro" — mas não pega "Sua conta Google está pendente de verificação" (nenhum dos quatro
  verbos-âncora aparece).
  Reais que caem aqui: "Fatura da Starlink", "Sua Fatura CELEBRE! ELO MAIS" (com S3f), "Seu carnê
  chegou" (também S2, forte), "Escolha como receber sua conta de luz" (veto `como receber` →
  `'nao'`, na verdade).
- S3f. Local-part financeira **genérica** (também usada por escolas/clínicas): `^(pagamento|pagamentos|
  financeiro|faturamento|cobranca|cobrancas|billing|cartao|cartoes)($|[._-])`.
- S7. Radical financeiro/utilidade como **prefixo ou sufixo** de um rótulo do domínio:
  `^(banco|bank|cartao|cartoes|fatura|cobranca|financeira|credito|consorcio|seguros?|energia|telecom)`
  ou `(pay|bank|card)$`. Positivos reais: `leroymerlinpay`, `faturaneoenergiabrasilia`,
  `bancoalfa`, `gamapay`, `cartaosamsclub`, `nubank`. Negativos: `nomadglobal`, `google`,
  `spotify`, `gastrobar`, `muffin` (`^gas`, `fin$`, `cred$`, `^luz` removidos).

Nenhum sinal → `'nao'` (sem chamada de corpo).

### Etapa 2 — confirmação no corpo (só para candidatos)

| Triagem | `parse()` devolve lançamento se… |
|---------|----------------------------------|
| `forte` | sempre, salvo evidência negativa; valor/data podem ficar `null` e o PDF tenta complementar |
| `fraco` | há **evidência de cobrança** nos primeiros `CABECA_EVIDENCIA` chars do texto ou nos anexos, conforme a tabela abaixo. Senão `null`. |

Evidências (E) e regra de suficiência:
- (E1) valor **> 0** ancorado por **âncora de cobrança**: `\b(valor a pagar|total a pagar|total da fatura|valor da fatura|valor do boleto|valor da conta|total da conta)\b`. `no valor de`, `valor:`, `total:` **não** são evidência (só extração) — "Você recebeu um Pix … no valor de R$ 500,00" não passa.
- (E2) **data válida** ancorada por `DATE_ANCHORS` (`\b(vencimento|vence|pague at[ée]|pagar at[ée]|data de vencimento)\b`), lendo **imediatamente após a âncora** um conector opcional `(em|no dia|dia|:|para o dia|—|-)?\s*` e então a data em qualquer formato aceito — inclusive **só dia** `(\d{1,2})\b` (1–31; próxima ocorrência ≤ 45 dias de `recebidoEm`; "vence dia 40" falha por estar fora de 1–31). "A mensalidade vence dia 10 — valor R$ 1.200,00" → E2 ✓.
- (E3) código de barras / linha digitável (regex de 47/48 dígitos existente).
- (E4) `pix copia e cola` / `chave pix` com uma moeda `R$ …,dd` **na mesma linha ou na linha seguinte**.
- (E5) `\bsua (fatura|conta)\b.{0,30}\b(est[áa]|segue) (anexa|anexada|em anexo)\b`.
- (E6) anexo cujo `filename` casa `fatura|invoice|boleto|cobran[çc]a`.

Suficiência para `fraco`: **E1, E3, E4, E5 ou E6 sozinhas bastam**. **E2 sozinha** basta só se o
assunto tem substantivo de cobrança de S6 (`fatura|boleto|mensalidade|cobrança|consórcio|parcela|
conta de …|IPTU|IPVA|DARF|DAS`); um candidato só por S7/S3f com apenas "vencimento + data" no corpo
(informativo de limite "Total da fatura atual: R$ 0,00 / Vencimento: dia 10") **não** cria.
Valor extraído `0,00` → `null` sempre. Limitação declarada: aviso de renovação de seguro com
"Vencimento da apólice dd/mm/aaaa" (S6 `seguro` + E2) **cria** — o prêmio é uma cobrança; o
usuário decide na revisão.

**Evidência negativa** (→ `null`, exceto S4), nas **3 primeiras linhas não vazias** do texto **ou no
assunto**: `isSettledPaymentSubject` ("Recebemos seu pagamento") · `\b(pesquisa de satisfa[çc][ãa]o|avalie (seu|nosso|o) atendimento)\b` · `\brecebeu (um|uma) (pix|transfer[êe]ncia|dep[óo]sito)\b` · `\b(pix|transfer[êe]ncia|dep[óo]sito|compra|rendimento|pagamento|estorno) .{0,25}(recebid|aprovad|realizad|agendad|efetuad|conclu[ií]d)` · `\bestorno\b`.
Isso é o que impede "Você recebeu um Pix de Fulano no valor de R$ 500,00", "Sua compra no valor de
R$ 89,90 foi aprovada", "Pagamento de boleto agendado", "Depósito recebido", "Estorno realizado"
(todos `fraco` por S7 `nubank`) de virarem lançamento.

Qualquer `null` em etapa 1 ou 2 executa `removerLancamentoDaMaquina`.

### `INSTITUTION_MAP` (enriquecimento, não porta de entrada)

Domínio → `{ nome, tipoPadrao }`. Semente inicial (domínios na implementação, um por linha,
com teste de que cada domínio resolve): Banco do Brasil `bb.com.br`, Caixa `caixa.gov.br`,
Santander `santander.com.br`, Itaú `itau.com.br` + `itaucard.com.br`, Bradesco `bradesco.com.br`,
Nubank `nubank.com.br`, Inter `bancointer.com.br`, C6 `c6bank.com.br`, BTG `btgpactual.com`,
Neon `neon.com.br`, PicPay `picpay.com`, Mercado Pago `mercadopago.com.br`, PagBank
`pagseguro.com.br`, Will `willbank.com.br`, XP `xpi.com.br`, Sicoob `sicoob.com.br`, Sicredi
`sicredi.com.br`, BRB `brb.com.br`, Pan `bancopan.com.br`, BMG `bancobmg.com.br`, Pefisa
`pefisa.com.br`, Sam's Club `cartaosamsclub.com.br`, Midway `midway.com.br` — `CARTAO`;
Claro `claro.com.br`, Vivo `vivo.com.br`, TIM `tim.com.br`, Enel `enel.com.br`, Neoenergia
`neoenergiabrasilia.com.br` + `faturaneoenergiabrasilia.com.br`, Light `light.com.br`, CPFL
`cpfl.com.br`, Cemig `cemig.com.br`, Sabesp `sabesp.com.br`, Comgás `comgas.com.br`, Starlink
`starlink.com`, Porto Seguro `portoseguro.com.br` — `OUTRO`. Casamento por **sufixo de domínio**
(`endsWith('.' + dominio) || === dominio`), o que cobre subdomínios e exclui `novidades.` só
pelo veto de remetente.

Desconhecido: `nome = deriveInstituicaoFromDomain(endereço)`; `tipoPadrao = 'OUTRO'` se algum
rótulo do domínio casa a lista **própria** `UTILIDADE_RE = /^(energia|eletr|luz|agua|saneamento|telecom)|(energia|eletrica|luz|agua|gas)$/`
(`neoenergia`, `comgas`, `cpfl`→não; `gastrobar`, `netflix` → não)
(independente de S7) ou o assunto tem `conta de (luz|energia|…)`; senão `undefined`.
`extractEmailAddress` sai do parser para `src/common/email-address.util.ts` (usado por triagem,
mapa e `deriveInstituicaoFromDomain`).

### Alvos medidos

- Amostra real de 24 (`__fixtures__/amostra-real-2026-09.json`, `remetente` no formato real
  `Nome <endereço>`): 12 financeiros → `forte|fraco`; 12 ruídos → `!== 'forte'`. Protótipo
  descartável das regras (`scratchpad/probe-triagem-spec-v5.ts`) com os casos abaixo → 0
  financeiros perdidos, 0 ruído forte, 0 adversarial forte (saída anexa ao PR).
- Instituições **fictícias, fora da lista** (`__fixtures__/instituicao-desconhecida/`, cada uma
  com corpo): "Banco Alfa" (`fatura@bancoalfa.com.br`, "Sua fatura Alfa Visa fechou") → forte,
  cria; "Cooperativa Beta" (`contato@coopbeta.coop.br`, "Boleto da mensalidade de outubro",
  corpo com linha digitável) → fraco, cria por E3; "Fintech Gama" (`no-reply@gamapay.com`,
  "Vencimento amanhã: R$ 89,90") → forte (S8), cria; "Loja Delta" (`ofertas@lojadelta.com.br`,
  "Fatura em 12x sem juros — aproveite") → veto. Nenhum em `INSTITUTION_MAP`.
- **Adversariais de assunto** (todos → `!== 'forte'`): "Sua conta Google está pendente de
  verificação", "Sua conta Spotify: nova senha disponível", "Parcelamento da fatura agora
  disponível no app", "Parcele sua fatura em 12x" (`todomundo@nubank.com.br`), "Dica: como
  entender sua fatura", "Empréstimo pré-aprovado para você", "Simule seu financiamento
  imobiliário", "Boleto: como funciona?", "Carne de primeira toda semana", "Fatura contestada —
  estamos analisando", "Sua fatura está disponível: aproveite 20% de desconto", "Fatura digital:
  saiba como aderir", "Cadastre-se na fatura por e-mail", "Fatura do mês: prefira o débito
  automático", "Agora você pode pagar boletos escaneando o código de barras", "Entenda o que é a
  linha digitável", `financeiro@escolax.com.br` "Reunião de pais", `faturamento@clinicay.com.br`
  "Confirmação de agendamento", "Promoção: R$ 20 de desconto vence hoje", "Oferta: R$ 0 de anuidade — vence hoje",
  "Ganhe R$ 50 de bônus até o vencimento", "Seu limite subiu para
  R$ 5.000", "Pix recebido de Fulano", "Resumo das suas compras", "Sua senha vence em 3 dias",
  "Código de verificação: 483920", "Aviso de interrupção de energia programada", "Renove seu seguro
  auto com desconto", "Alerta de segurança: novo acesso detectado" (29 no total).
- **Adversariais de corpo** (fraco → etapa 2 deve devolver `null`; fixtures em
  `__fixtures__/adversarial-corpo/`): "Pix recebido" (`Valor: R$ 500,00`), "Compra aprovada"
  (`Valor: R$ 89,90`), "Transferência realizada" (`Valor: R$ 300,00`), "Rendimento da caixinha"
  (`Valor total: R$ 5.012,34`), "Seu cartão foi entregue" ("validade/vencimento 12/30" sem
  data válida por âncora de cobrança), "Resumo das suas compras" (`Subtotal: R$ 120,00`), "Sua
  senha vence em 3 dias" (data ancorada por `vence em` **existe** → precisa do veto de assunto
  `\bsenha\b`, adicionado aos vetos), "Aviso de interrupção de energia programada" de `avisos@energiaxyz.com.br` (S7 `energia`; sem E1–E6 — de `enel.com.br` nem chega à etapa 2).
- Limitação declarada: assuntos em inglês ("Your statement is ready") → `'nao'`.

## Extração — `parse()` e `complementarComTexto()`

**Tipo (`FATURA_CARTAO` vs `DESPESA`)** — conteúdo decide, lista desempata:
- `tipoPadrao === 'OUTRO'` (mapeado ou inferido por utilidade) → `DESPESA`, sempre.
- Senão `FATURA_CARTAO` se: `isCardInvoiceSubject(assunto)` OU `\bcart(ão|ao|[õo]es)\b` a ≤ 40
  chars de `\bfatura\b` nos primeiros `CABECA_TIPO` (600) chars do texto OU (`tipoPadrao === 'CARTAO'`
  e assunto com `\bfaturas?\b` **sem** produto não-cartão `cons[óo]rcio|empr[ée]stimo|financiamento|
  seguro|presta[çc][ãa]o|consignad[oa]`) OU bandeira `\b(visa|mastercard|master|amex|hipercard)\b` a ≤ 40
  chars de `\bfatura\b` no assunto ou texto-cabeça (`elo` fica fora por ser palavra comum).
- Caso contrário `DESPESA`.

**Valor**
- Âncoras (todas com fronteira de palavra à esquerda — `Subtotal:` não casa `total:`): as 5
  atuais + `no valor de` · `valor:` · `total:` · `valor da conta` · `valor do boleto` ·
  `total da conta` · `valor da fatura`. `valor:`/`total:` só extraem; não são evidência (etapa 2).
- Moeda com `R$` opcional **apenas quando ancorada**: `(?:R\$\s*)?((?:\d{1,3}(?:\.\d{3})*|\d+),\d{2})`.
  Fallback não ancorado continua exigindo `R$` e ocorrência única (inalterado).
- Segmentos de parcelamento nunca fornecem valor: o trecho **após a âncora, na mesma linha**, é
  descartado se começar (até 15 chars) com `ap[óo]s`, `m[ií]nimo`, ou contiver `\d+\s*(x|vezes)\s+de`
  / `parcelas?\s+de` **antes** da primeira moeda. Isso preserva os testes existentes
  ("Pagamento mínimo R$ 123,45 Total da fatura R$ 1.234,56" → 1234.56; "…após o vencimento R$ X
  Valor a pagar até o vencimento R$ Y" → Y).
- Fallback de próxima linha só quando a próxima linha é não vazia, **não** contém
  `\d+\s*(x|vezes)\s+de|parcelas?\s+de|m[ií]nimo` e **não** contém outra âncora de valor.
  Leroy: "Valor total: 520,61" já casa na própria linha (R$ opcional); a linha "OPÇÃO 1: 12 vezes
  de R$ 86,33" nunca é consultada.

**Data de vencimento**
- `DATE_ANCHORS` passa a ser **uma lista só**, usada por extração e por E2: `vencimento` · `vence`
  · `pague até` · `pagar até` · `data de vencimento` (as formas atuais `vence em/dia` viram o
  conector opcional lido após a âncora: `(em|no dia|dia|:|para o dia|—|-)?`).
- Forma **só dia** (`dia 10`, sem mês) aceita apenas após âncora: próxima ocorrência do dia a partir
  de `recebidoEm`, no máximo 45 dias à frente; fora de 1–31 ou além de 45 dias → descartada.
- Novos formatos **só em linha ancorada** (nunca no fallback de corpo inteiro, para "Parcela 3/12"
  não virar 3 de dezembro): `dd/mm` sem ano — `(\d{1,2})/(\d{1,2})(?![/\d])`, avaliado **depois**
  dos formatos com ano ("10/10/2025" nunca é lido como 10/10 + ano inferido) — e `dd de <mês>`
  sem ano. Data inválida (`31/02`, `29/02` em ano não bissexto) é descartada, não rolada.
- Ano inferido: entre `ano(recebidoEm) − 1`, `ano(recebidoEm)` e `ano(recebidoEm) + 1`, o que
  minimiza `|data − recebidoEm|`. Cobre "10/01" recebido em 28/12/2026 → 2027-01-10 e "venceu
  28/12" recebido em 05/01/2027 → 2026-12-28.
- `ParsedLancamento` ganha `dataEncontrada: boolean` (hoje interno como `encontradaNoCorpo`).

**PDF anexo — `GmailApiClient.fetchPdfAttachmentText(refreshToken, messageId, anexo)`**
- `pdf-parse` v2 usa `pdfjs-dist`, que carrega via ESM dinâmico; sob Jest isso só funciona com a
  flag `NODE_OPTIONS=--experimental-vm-modules` (já embutida nos scripts `test`/`test:watch`/
  `test:cov` do `package.json`) — sem ela, o teste com PDF real falha mesmo com o código correto.
- `anexo` vem dos metadados do passo 2: primeira parte com `mimeType === 'application/pdf'` ou
  `filename` terminando em `.pdf` (Santander manda `octet-stream`), `size ≤ 5 MB`.
- `attachments.get` (erro do `attachments.get` segue `classificarErroGmail`; só o parse do buffer é
  "PDF ilegível"). Buffer → `pdf-parse` **v2** (`pdf-parse@2.4.5`, já instalado; **não** copiar
  `rag/document-processor.service.ts`, que usa a API v1 e está incompatível com a versão
  instalada — registrar como dívida separada):
  ```ts
  const parser = new PDFParse({ data: new Uint8Array(buffer) });
  try {
    const { text } = await withTimeout(parser.getText({ first: 3 }), 10_000);   // helper NOVO: src/common/with-timeout.ts (Promise.race; lança TimeoutError)
    return text;
  } catch (e) {
    if (e instanceof PasswordException || e instanceof InvalidPDFException || e instanceof FormatError
        || e instanceof TimeoutError) return null;                                  // permanente → valor fica null
    throw e;
  } finally { await parser.destroy(); }
  ```
- `complementarComTexto(parsed, textoPdf)`: preenche **apenas** `valor` se `null` e
  `dataVencimento` se `!dataEncontrada`, com as mesmas âncoras; nunca sobrescreve o corpo.

## Reprocessamento e escrita idempotente

- `FINANCE_PARSER_VERSION = 2` (constante exportada). `null` cobre todo o legado.
- Passo (B) roda a cada `syncUser`, depois dos novos, `take: 50` por usuário por ciclo, do mais
  recente para o mais antigo. Com cron de 20 min, 500 summaries zeram em ~3 h.
- **Classificação de erros** — novo helper `classificarErroGmail(err): 'transitorio-conta' |
  'transitorio-mensagem' | 'permanente'` em `gmail-error.util.ts`, contra a forma real do gaxios 7
  (`googleapis-common/node_modules/gaxios@7`): `status = statusHttpDoErroGmail(err)`;
  `codes = {err.code, err.error?.code, err.cause?.code}` (strings); `nomes = {err.name, err.error?.name,
  err.cause?.name}` (**conjunto** — um timeout real tem `err.name === 'Error'` e `err.error.name ===
  'AbortError'`); `ehGaxios = err instanceof GaxiosError || 'config' in err || Symbol.for('gaxios-gaxios-error') in err`.
  | Condição (na ordem) | Classe | Ação em (B) |
  |---------------------|--------|-------------|
  | `!ehGaxios` (exceção nossa: parser, PDF, Prisma exceto P2002, `HttpException` do Nest) | permanente | carimba `V`, `tentativas = 0`, log `error` (PDF: `debug`) |
  | `status ∈ {401, 403, 429}` | transitório-conta | `tentativas += 1`; **interrompe o lote** (afeta todos) |
  | GaxiosError do endpoint de token (invalid_grant, HTTP 400) | transitório-conta | idem |
  | `codes ∩ {ECONNRESET, ETIMEDOUT, ECONNREFUSED, EAI_AGAIN, ENOTFOUND, EPIPE} ≠ ∅` ou `nomes ∩ {AbortError, TimeoutError} ≠ ∅` ou (`ehGaxios` e `status === undefined`) | transitório-conta (rede) | idem |
  | `500 ≤ status ≤ 599` | transitório-mensagem (a API do Gmail devolve 5xx persistente para mensagens isoladas) | `tentativas += 1`; **não** carimba; **segue** para a próxima |
  | `status === 404` (mensagem apagada) | permanente | carimba `V`, `tentativas = 0`, `removerLancamentoDaMaquina` |
  | outro 4xx | permanente | carimba `V`, `tentativas = 0`, log `error` |
  Casos de teste do helper (fixtures construídas como `GaxiosError` reais, não objetos soltos):
  429 → conta; 401 → conta; timeout com `error.name = 'AbortError'` → conta; `ENOTFOUND` → conta;
  `ECONNRESET` → conta; 503 → mensagem; 404 → permanente; `TypeError` → permanente; `GaxiosError`
  sem status nem code → conta.
- **Fila sem perda e sem bloqueio:** (B) seleciona `parserFinancasVersao IS NULL OR < V`,
  `orderBy: [{ parserFinancasTentativas: 'asc' }, { recebidoEm: 'desc' }]`, `take: 50`. Erro
  transitório **nunca carimba** — o e-mail permanece elegível para sempre; uma mensagem venenosa
  (5xx persistente) apenas acumula `tentativas` e afunda para o fim da fila, custando 1 chamada por
  ciclo quando a fila está vazia. Sem contador de desistência, sem reset. Sucesso ou erro permanente
  zera `tentativas`. No passo (A), falha transitória em `processar` grava `parserFinancasVersao:
  null`, `tentativas: 1`.
- **Concorrência:** `syncUser` só é chamado pelo scheduler (`grep` confirma), que tem guard
  `running` de instância única; (B) herda. Premissa: uma réplica do backend.
- Escrita por `(userId, emailMessageId)`:
  - sem lançamento → `create`;
  - `EMAIL_PARSER` + `PENDENTE_REVISAO` → `updateMany({ where: { userId, emailMessageId, origem, status }, data })`
    de `tipo, descricao, instituicao, valor, dataVencimento, dataCompetencia, codigoBarras`;
  - `triagem === 'nao'` ou `parse() === null` → `removerLancamentoDaMaquina`;
  - `CONFIRMADO`, `IGNORADO` ou `origem MANUAL` → intocado.
- P2002 continua tratado como corrida benigna.

## Marcador Gmail

- Nome fixo `Sincro/Finanças`. Passo 0 de `syncUser`: `labels.list` → `labelId` cujo `name ===
  'Sincro/Finanças'` (comparação NFC, case-insensitive). Sem esse label → `Set` vazio, sem
  chamada adicional. Com label → `messages.list({ labelIds: [labelId], q: 'newer_than:90d',
  maxResults: 100 })` → `Set<gmailMessageId>` (sem paginação; limite declarado: 100 e-mails
  rotulados nos últimos 90 dias). Evita depender da sintaxe `label:"…/…"` na query, que a
  documentação não especifica para rótulos aninhados/acentuados.
- **Re-enfileiramento (idempotente por evento):** todo `gmailMessageId` do `Set` cujo `EmailSummary`
  ainda **não** tem o `labelId` em `labelIds` volta a `parserFinancasVersao = null` — um
  `$executeRaw` (`UPDATE … WHERE … AND NOT (label_ids @> ARRAY[$1])`; o Prisma não expressa isso
  sem relação). Ao processar com S4, `labelIds` recebe o `labelId`, então o mesmo e-mail **não** é
  re-enfileirado nos ciclos seguintes — apagar o lançamento depois (`DELETE /lancamentos/:id`) não o
  ressuscita. Remover o rótulo no Gmail e recolocá-lo também não re-enfileira (limitação declarada;
  orientar `IGNORADO` em vez de apagar). E-mail rotulado com lançamento `CONFIRMADO` é reprocessado
  mas o lançamento não é tocado (regra de escrita).
- Falha transitória no passo 0 → log `warn`, `Set` vazio, ciclo segue (o marcador só adiciona). Mas
  não é tratada como "hoje não tem marcador": `resolverMarcador` devolve `indisponivel: true`, e com
  isso (A) carimba `parserFinancasVersao = null` (não `FINANCE_PARSER_VERSION`) nos e-mails novos
  deste ciclo — mesmo chamando `processar()` normalmente, para o lançamento existir já — e (B) é
  pulado neste ciclo inteiro (log `warn`, sem consultar `emailSummary.findMany`); sem isso, um
  e-mail rotulado pelo usuário e processado agora com o `Set` vazio carimbaria versão atual e nunca
  mais seria revisitado, porque o `labelId` já chega em `email.labelIds` do Gmail e o re-enfileiramento
  do passo 0 só olha `NOT (label_ids @> ARRAY[...])`.
- `FetchedEmail.labelIds` passa a ser preenchido por `fetchMessages` e persistido em
  `EmailSummary.labelIds` (informativo; a decisão usa o `Set`).
- Limitação declarada: e-mail com mais de 90 dias, ou além dos 100 mais recentes rotulados, não é
  revisitado pelo marcador.
- Limitação declarada: e-mail com o marcador mas classificado pelo Gmail em
  Promoções/Social/Atualizações/Fóruns é descartado por NOISE_LABELS antes de virar
  EmailSummary — o marcador não o alcança.

## Estratégia de testes

**Unitários — triagem (`finance-email-detector.spec.ts`, novo)**
- Tabela real de 24 (`__fixtures__/amostra-real-2026-09.json`, `remetente` = header `From`
  real): 12 → `forte|fraco`; 12 → `!== 'forte'`.
- Instituições fictícias (4) nomeadas em "Alvos medidos", um `it` cada.
- Cada veto individual: extrato, débito automático concluído, recibo de pedido, pedido faturado,
  pesquisa, convite, novidades, descubra, conheça, ganhe, sorteio, cashback, `% off`, sem juros,
  simule, pré-aprovado, contestação, como funciona, dica; remetentes `novidades.`, `news@`,
  `newsletter`, `marketing@`, `promo`, `ofertas@`, `comunicacao@`.
- S4 anula veto ("Extrato…" marcado → `forte`).
- Precedência veto > sinal ("Sua fatura está disponível: aproveite 20% de desconto" → `'nao'`).
- Vetos duros individuais: `cupom`, `em análise`, `disputa`, `aderência/adesão`, `código de
  segurança/acesso`, `débito automático cadastrado/ativado`, `pedido enviado/entregue`, `agendado`,
  `estorno`, `recebido`; vetos brandos anulados por S1a ("Sua fatura chegou. Saiba como pagar" →
  `forte`) e não anulados por S2/S3 ("Boleto emitido — descubra o app" → `'nao'`).
- Veto `seu pedido`; S6 positivos para `IPTU`, `IPVA`, `DAS` (maiúsculas), `sua conta chegou`,
  `conta de luz`, `seguro`, `linha digitável`, `código de barras`, `cobrança`, `consórcio`,
  `financiamento`, `empréstimo`, `prestação`, `parcelas`, `anuidade`; S1b sem período e sem veto
  ("Fatura digital da sua loja favorita") → `fraco`; S7 negativos `gastrobar`, `muffin`.
- S8 negativo ("Seu limite subiu para R$ 5.000" → não forte).
- Adversariais de assunto (29) e de corpo (8) nomeados em "Alvos medidos", um `it` cada.
- Fronteira Unicode: `carnê` casa, `carne` não; `venc.` casa; `da fatura` não casa `a fatura`.
- S3/S7 sobre endereço extraído: `Pefisa <pagamento@pefisa.com.br>` → `forte`.
- Assunto em NFD → mesmo resultado que NFC.

**Unitários — parser (`email-finance-regex-parser.service.spec.ts`)**
- Fixtures reais (texto legível, dados pessoais mascarados):
  `nubank-fatura-fechada.txt` → `FATURA_CARTAO`, `valor: null`, `2026-09-15`;
  `santander-fatura-por-email.txt` → `FATURA_CARTAO` (cartão no corpo), `111.46`, `2026-08-10`;
  `leroy-pefisa-celebre.txt` + variante minificada → `FATURA_CARTAO`, `520.61`, `2026-09-17`,
  nunca 86.33; `sams-vence-em-breve.txt`; `starlink-fatura.txt` (fraco aceito por E6 — anexo `fatura`; E5 se o corpo
  tiver a frase); `porto-consorcio.txt` (fraco aceito por "no valor de … vencimento");
  `neoenergia-escolha-conta-luz.txt` (fraco rejeitado); `pagamento-recebido.txt` (evidência
  negativa em forte → `null`; com S4 → cria).
- Evidência negativa no corpo: `pesquisa de satisfação`, `avalie seu atendimento`, `pix recebido`.
- E2 "vence dia 10" (só dia) → cria com data inferida; "vence dia 40" → não é E2 (fora de 1–31);
  "vence dia 5" recebido dia 20 com 50 dias até o próximo dia 5 → descartada (> 45 dias).
- E2 sozinha: cria com assunto `fatura` (S6); **não** cria com candidato só-S7 ("Total da fatura
  atual: R$ 0,00 / Vencimento: dia 10" de `nubank`); valor `0,00` → `null`.
- E4: pix copia e cola + moeda na linha seguinte → E4; a 3 linhas de distância → não.
- Evidência negativa: "Você recebeu um Pix…no valor de R$ 500,00", "Sua compra…foi aprovada",
  "Depósito recebido", "Estorno realizado" → `null`.
- Constantes: tag HTML no char 301 não converte; texto no char 1 501 não é evidência; `cartão` no
  char 601 não muda tipo; `orderBy` de (B) verificado com 3 summaries.
- PDF: `InvalidPDFException` e `FormatError` → `null`.
- Evidência de cobrança E1–E6, um `it` positivo por tipo, e negativos: `valor:`/`total:`/`vencimento`
  solto **não** contam; `Subtotal:` não casa `total:`; fallback não ancorado continua exigindo `R$`.
- Âncoras novas de valor (`no valor de`, `valor:`, `total:`, `valor da conta`, `valor do boleto`,
  `total da conta`) e de data (`vence no dia`, `vencimento:`, `vence em`, `data de vencimento`).
- Segmento de parcelamento ignorado; testes existentes de "mínimo"/"após o vencimento" continuam
  verdes; fallback de próxima linha recusa linha de parcelamento e linha com outra âncora.
- Ano: "10/01" @ 28/12/2026 → 2027-01-10; "15 de setembro" @ 08/09/2026 → 2026-09-15;
  "venceu 28/12" @ 05/01/2027 → 2026-12-28; "Parcela 3/12" sem âncora → não é data;
  "Vencimento: 10/10/2025" @ 01/09/2026 → 2025-10-10 (formato com ano vence); "31/02" → descartada.
- Tipo: bandeira `Visa` → `FATURA_CARTAO`; conta de luz com "pague com cartão de crédito" no
  corpo → `DESPESA` (utilidade inferida); `elo` isolado não muda tipo.
- `complementarComTexto` preenche só `null`/`!dataEncontrada`.
- Regressão: "Parcele sua fatura em 12x" de remetente desconhecido → não cria.
- **Testes existentes cuja expectativa muda de propósito** (atualizar, não apagar): `it.each`
  de "Nova função: fatura em PDF já disponível"/"Parcelamento da fatura agora disponível no
  app" passa de `tipo === 'DESPESA'` para `null` (veto/`da`); `describe('matches')` vira
  `describe('triagem')` e "Sua fatura já está fechada", "Nova fatura disponível", "Sua fatura de
  energia elétrica chegou", "Nova fatura de condomínio disponível" passam a `forte`;
  `describe('processEmail')` migra para `FinanceEmailProcessor` e "never creates a second
  lançamento" vira "faz `updateMany` do pendente".

**Unitários — `FinanceEmailProcessor`** (Prisma e Gmail mockados): create · updateMany de
pendente · remove em `'nao'` · remove em `parse() === null` · não toca confirmado/ignorado/manual
· PDF consultado só quando falta valor ou data · PDF com erro → segue com `null` · 3 páginas.

**Unitários — `EmailSyncService` + `gmail-error.util`**: novos e-mails carimbam versão e
`labelIds`; falha transitória em (A) grava `null`; passo (B) pega `null` e `< versão`, respeita
`take: 50`; erro permanente carimba e zera tentativas; 429/5xx/`ECONNRESET`/`ETIMEDOUT`
incrementam tentativas e **não** carimbam;
404 carimba + remove lançamento da máquina; transitório-conta interrompe o lote sem carimbar;
transitório-mensagem (503) incrementa e segue sem carimbar; fila ordena por `tentativas asc,
recebidoEm desc` (venenosa vai ao fim); passo 0 re-enfileira e-mail carimbado e rotulado depois,
e **não** re-enfileira quem já tem o `labelId` persistido; passo 0 resolve `labelId` (comparação NFC/case-insensitive) e `Set` uma vez; label
ausente → `Set` vazio; falha transitória no passo 0 → `warn` e ciclo segue; e-mail marcado sem
outro sinal → `forte`; `classificarErroGmail` com os 9 casos enumerados na tabela.

**Unitários — `GmailApiClient`**: `fetchFullBodyComAnexos` converte `text/plain` que contém
HTML (com BOM, com preheader antes de `<html>`, começando em `<p>`/`<body>`/`<!--`) e **não**
converte texto plano genuíno; devolve metadados de anexos sem baixar; `INSTITUTION_MAP` resolve
por sufixo (`leroymerlinpay.pefisa.com.br` → Pefisa/`CARTAO`); `fetchPdfAttachmentText` escolhe por mimeType **ou** extensão,
respeita 5 MB, devolve `null` em PDF protegido (fixture gerada com senha) e em timeout.

**Verificação em produção (manual, após deploy):**
```sql
select gmail_message_id, assunto, parser_financas_versao from resumos_email
 where gmail_message_id in ('19fceaf2b80763e0','1a07f4e5e9882fe6','1a0a4f412c11e93b');
select descricao, tipo, valor, data_vencimento, status from lancamentos_financeiros
 where origem = 'EMAIL_PARSER' order by criado_em desc limit 20;
```
Esperado: os três com versão 2; Nubank 08/09 (`valor null`, venc. 15/09), Santander (`111.46`,
10/08), Leroy (`520.61`, 17/09) em `PENDENTE_REVISAO`; nenhum "Extrato".

## Critérios de sucesso

- Amostra real: 12/12 capturados, 0/12 ruídos, sem valor fabricado (teste automatizado).
- Medido na verificação final (Task 14, 2026-09-16): `cd backend && npm test` → 49 suítes / 732
  testes verdes; `triagem()` real sobre `__fixtures__/amostra-real-2026-09.json` → 12/12 financeiros
  viram candidato (`forte`/`fraco`), 0/12 ruídos viram `forte` indevidamente.
- Instituições fictícias fora da lista: 3/3 cobranças criam lançamento, 1/1 marketing não;
  29 adversariais de assunto não são `forte`; 8 adversariais de corpo não criam.
- Após um ciclo completo de reprocessamento na VPS, os e-mails de fatura já visíveis no
  app aparecem em "Pendentes de revisão".
- `flutter`/mobile inalterado; `npm test` do backend verde; `prisma migrate` aplicada.
- Nenhuma chamada a LLM no caminho de finanças.
