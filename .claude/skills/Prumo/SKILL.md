---
name: prumo
description: >-
  Planejamento enxuto + economia de contexto/tokens para construir software com Claude Code.
  Use SEMPRE que o dono for CONSTRUIR, MEXER ou EVOLUIR um código/app/site/sistema/SaaS com IA e
  quiser acertar na primeira e NÃO queimar a assinatura em tokens — "vou fazer uma feature",
  "preciso mexer nesse projeto", "a IA fica em loop e gasta um monte de token", "como planejo
  isso antes de codar", "monta um CLAUDE.md pro meu projeto", "quais arquivos eu abro pra essa
  tarefa", "economizar token no Claude Code", "por onde começo esse build". Prumo NÃO escreve o
  código nem depura bug — ele deixa a obra "no prumo" ANTES e DURANTE: plano curto, contexto
  pequeno, um passo verificável por vez, e mede onde o token vaza. Tudo offline e local em .prumo/.
---

# Prumo — construir com Claude Code no prumo (plano enxuto + economia de token)

O **fio de prumo** é a ferramenta simples que mantém a parede reta e verdadeira. O **Prumo** faz o
mesmo com quem constrói software usando Claude Code: mantém o trabalho **no prumo** — um plano curto,
o contexto pequeno, e um passo de cada vez — para a IA **acertar na primeira** e você **não estourar
tokens** indo em círculos.

É a peça que faltava no cinto de quem constrói com IA:
- **Estaleiro** ESCREVE código (a tripulação), **Rastro** DEPURA um bug existente.
- **Prumo** é o passo ANTES e DURANTE o build: **planejar direito, abrir só os arquivos certos, e
  não deixar a IA passear** — que é onde o token some.

> A dor nº1 desta comunidade: "a IA vai em círculos, mexe em coisa demais e queima a assinatura".
> Projeto sem disciplina gasta 4–6× mais token. Prumo é a disciplina — em conversa, sem você virar
> engenheiro de contexto.

## Quando usar (gatilhos)
- "Vou construir/adicionar uma feature", "preciso mexer nesse sistema", "por onde começo?"
- "A IA fica em loop / gastando token / mexendo em arquivo que não devia."
- "Monta/arruma um CLAUDE.md pro meu projeto." · "Como economizo token no Claude Code?"
- "Quais arquivos eu abro pra essa tarefa?" · "Faz um plano antes de eu mandar a IA codar."
- Antes de soltar Estaleiro/qualquer IA num build → passe pelo **Pré-voo** do Prumo primeiro.

**NÃO é o Prumo quando:** escrever o código em si (→ Estaleiro), caçar um bug que já quebrou
(→ Rastro), criar uma skill/agente instalável (→ Molde), escrever/guardar prompts (→ Prisma),
escopar automação vendida a um cliente (→ Planta). Prumo é planejamento + economia de contexto do
build do PRÓPRIO dono.

## Primeira vez (setup) — obrigatório antes de tudo
Se **não existir `.prumo/config.md` na raiz do projeto**, rode o setup de primeira execução:
1. Leia `setup/SETUP.md` e siga o roteiro (é uma conversa curta em PT-BR).
2. Ele grava `.prumo/config.md` (git-ignored) com nome/stack/como roda o projeto e **se autodestrói**
   (apaga a pasta `setup/`).
Se `.prumo/config.md` já existe, pule direto para os modos.

> **Onde o Prumo guarda tudo:** numa pasta `.prumo/` na **raiz do projeto** do dono (não dentro da
> skill). O motor acha a raiz sozinho (variável `CLAUDE_PROJECT_DIR` ou subindo até achar `.git`/`.claude`).
> Rode o `prumo.py` de dentro do projeto do dono. Dados 100% locais, nada vai pra internet.

## O motor
Toda conta exata é feita por `scripts/prumo.py` (Python puro, **offline**, sem instalar nada, sem API).
A IA (você) conversa, decide e escreve; o motor mede, guarda e verifica. Ajuda geral:
```
python3 scripts/prumo.py --help
```

## Os 6 modos

### 1. Planejar — o plano curto antes de codar
O erro que mais queima token é mandar a IA construir sem um alvo. Aqui você vira o pedido vago num
**plano enxuto**: objetivo (o quê/por quê), **arquivos-alvo** (o conjunto pequeno que vai mexer),
**passos verificáveis** em 3 fases (Preparar → Construir → Testar), **critério de aceite** (como saber
que terminou) e **fora de escopo** (o que NÃO fazer agora — isso trava a IA de sair passeando).
Leia `references/planejar.md`. Nunca invente o que o dono não disse — pergunte.
```
python3 scripts/prumo.py plano-nova --titulo "..." --objetivo "..." --aceite "..." --fora "a; b"
python3 scripts/prumo.py plano-alvo --slug <slug> --add "src/x.ts,src/y.ts"
python3 scripts/prumo.py passo-add --slug <slug> --fase setup|impl|teste --texto "..." --arquivo "..." --aceite "..."
python3 scripts/prumo.py plano --slug <slug>          # mostra o plano
python3 scripts/prumo.py planos                        # lista os planos
```

### 2. Contexto (raio-x) — abra só os arquivos certos
Jogar o repositório inteiro no contexto é o maior desperdício. O raio-x mede o **peso** do projeto
(arquivos, linhas, tokens estimados), mostra **onde o contexto mora** (pastas/arquivos mais pesados)
e — se você disser a tarefa — sugere o **conjunto ENXUTO** de arquivos a abrir. Leia `references/contexto.md`.
```
python3 scripts/prumo.py raiox                                  # peso geral do projeto
python3 scripts/prumo.py raiox --tarefa "corrigir o login" --top 6
```
Depois, use esses arquivos como os `--add` do plano (arquivos-alvo). **Não abra o repo todo.**

### 3. Passo a passo — um verificável por vez
Construir tudo de uma vez é onde a IA se perde e refaz. Aqui você caminha o plano **um passo por vez**,
verificando cada um antes do próximo — o ritmo que não deixa o token vazar. Leia `references/planejar.md` (fim).
```
python3 scripts/prumo.py passo-proximo --slug <slug>     # mostra SÓ o próximo passo + como verificar
python3 scripts/prumo.py passo-concluir --slug <slug> --id N
```

### 4. Memória do projeto (CLAUDE.md) — o maior poupador de token
O `CLAUDE.md` na raiz é lido **toda sessão**: um bom arquivo faz a IA parar de redescobrir o projeto
do zero (economia enorme); um arquivo inchado ou vago desperdiça. Aqui você **audita** o CLAUDE.md
existente (orçamento de ~3000 tokens, seções que faltam, comandos rodáveis, placeholders, prosa demais)
ou **gera um esqueleto**. Leia `references/claude_md.md`.
```
python3 scripts/prumo.py claudemd-auditar         # nota + o que arrumar no CLAUDE.md do projeto
python3 scripts/prumo.py claudemd-modelo          # esqueleto pronto pra preencher
```
Depois de gerar o esqueleto, preencha cada `[colchete]` COM o dono (pergunte o que não souber).

### 5. Pré-voo — a porta antes de soltar a IA
Antes de mandar qualquer IA construir, passe pelo **pré-voo**: tem plano? o contexto está enxuto?
tem critério de aceite? tem CLAUDE.md dentro do orçamento? Dá um veredito 🟢/🟡/🔴 e aponta o que
falta. É aqui que você impede o vazamento de token **antes** dele acontecer.
```
python3 scripts/prumo.py checar --slug <slug>
```
Só solte a IA (Estaleiro, /edit, o que for) quando o pré-voo estiver 🟢.

### 6. Painel & Economia — onde o token vaza
Um diário simples das suas sessões de trabalho. Registre cada tarefa e o **desfecho honesto**
(entregou / travou / entrou em loop) e, se souber, o token gasto. O painel mostra quantas sessões
travam, quanto token queima e **quais assuntos mais dão loop** — esses são os que precisam de um
CLAUDE.md melhor ou um plano mais enxuto. Leia `references/anti_desperdicio.md`.
```
python3 scripts/prumo.py sessao-iniciar --tarefa "..."
python3 scripts/prumo.py sessao-fechar --id N --desfecho entregou|travou|loop --tokens 8000 --nota "..."
python3 scripts/prumo.py sessoes        # histórico
python3 scripts/prumo.py stats          # painel de economia
```

## Fluxo recomendado (a "receita do prumo")
Quando o dono disser "vou construir X" ou "preciso mexer nisso":
1. **Raio-x** com a tarefa → descubra os poucos arquivos que importam (`raiox --tarefa`).
2. **Planeje** curto: objetivo, arquivos-alvo (os do raio-x), passos, aceite, fora-de-escopo (`plano-nova` + `plano-alvo` + `passo-add`).
3. **Memória**: se não há CLAUDE.md (ou está ruim), gere/arrume (`claudemd-modelo`/`claudemd-auditar`).
4. **Pré-voo** (`checar --slug`): só avance no 🟢.
5. **Construa um passo por vez** (`passo-proximo` → faz → verifica → `passo-concluir`), usando SÓ os arquivos-alvo.
6. **Feche a sessão** com o desfecho honesto (`sessao-fechar`) e, de tempos em tempos, olhe o `stats`.

## Regras de ouro (nunca quebre)
- **Plano antes de código.** Sem alvo, a IA passeia e queima token. Primeiro o plano curto.
- **Contexto enxuto.** Abra só os arquivos-alvo. Nunca jogue o repositório inteiro no contexto.
- **Um passo verificável por vez.** Faça, verifique, siga. Não construa tudo de uma vez.
- **Nunca invente.** O que o dono não disse (arquivo, regra, comando), pergunte — não chute.
- **Meça, não ache.** O desperdício aparece no painel; decisão vem do dado, não do achismo.
- **A IA sugere, o dono aprova e roda.** O Prumo planeja e mede; quem manda construir é o dono.
- **Tudo local.** `.prumo/` fica no projeto do dono; nada é enviado pra internet.

## Referências
- `references/planejar.md` — como escrever um plano/spec enxuto e caminhar passo a passo.
- `references/contexto.md` — economia de contexto/tokens: working-set, `.claudeignore`, /clear vs /compact, reuso.
- `references/claude_md.md` — o checklist do CLAUDE.md bem-feito (seções, orçamento, comandos, cuidados).
- `references/prompts.md` — como pedir um build pra IA em formato enxuto (Tarefa/Stack/Arquivos/Saída/Aceite).
- `references/anti_desperdicio.md` — os padrões que queimam token e como sair deles.
