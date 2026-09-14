# CLAUDE.md — a memória do projeto (o maior poupador de token)

O `CLAUDE.md` na raiz do projeto é lido pela IA em **toda sessão**. É a memória permanente: o que é o
projeto, como roda, que convenções seguir, o que NÃO fazer. Um bom CLAUDE.md faz a IA **parar de
redescobrir o projeto do zero** toda vez — economia gigante. Um arquivo inchado ou vago faz o oposto.

Por isso ele merece cuidado: **cada linha aqui é token gasto em toda conversa**. A meta é enxuto e
certeiro — só o que muda o comportamento da IA pra melhor.

## O orçamento: ~3000 tokens
- **Até ~3000 tokens** (≈ 2000 palavras): saudável.
- **3000–4000**: começando a pesar — enxugue as seções mais verborrágicas.
- **Acima de 4000**: caro demais. Isso é carregado SEMPRE. Corte o supérfluo, ou quebre em um
  CLAUDE.md raiz curto + arquivos por subpasta importados com `@caminho`.

Audite a qualquer momento:
```
python3 scripts/prumo.py claudemd-auditar
```
Ele dá o tamanho em tokens, aponta seções que faltam, placeholders esquecidos, comandos ausentes e
prosa demais, e fecha com um veredito 🟢/🟡/🔴.

## As seções que valem o token
Um CLAUDE.md útil tem (gere o esqueleto com `claudemd-modelo` e preencha com o dono):

1. **Visão do projeto** — o que é e pra quem, em 1-2 linhas. Estado (produção/construção).
2. **Stack** — linguagem, framework, banco, onde roda. A IA para de perguntar/adivinhar.
3. **Comandos (os exatos)** — rodar, testar, buildar, lint. Em bloco de código, comandos REAIS
   (`npm run dev`, `pytest`), não "rode os testes". Isso poupa a IA de descobrir sozinha.
4. **Arquitetura / estrutura** — o que vive em cada pasta e como as partes conversam. 3-6 linhas.
5. **Convenções** — estilo (funções pequenas? TypeScript estrito?), nomes, o "sempre faça".
6. **Cuidados / armadilhas** — as regras DE NÃO fazer: "não edite arquivos gerados", "não use a lib
   X descontinuada", a pegadinha conhecida. **Isso evita a IA repetir erros** — o token mais bem gasto.
7. **Como testar** — como rodar 1 teste e como saber que passou.

## Escreva pra máquina ler barato
- **Bullets, tabelas e blocos de código** — não prosa corrida. É mais curto e a IA acha mais rápido.
- **Comandos em formato compacto:** `` `npm test`  # roda a suíte `` em vez de um parágrafo.
- **Sem placeholder esquecido.** `[PREENCHER]`, `TODO`, `xxxx` — a IA obedece isso ao pé da letra e
  se confunde. Preencha ou apague antes de salvar.
- **Sem repetição e sem contradição.** Se duas linhas dizem coisas diferentes, a IA escolhe a errada.
- **Só o que muda o comportamento.** Curiosidade histórica, texto de marketing, óbvios — fora.

## Como conduzir (você, a IA)
1. Rode `claudemd-auditar`. Se não existe, rode `claudemd-modelo` pra ter o esqueleto.
2. Preencha cada `[colchete]` **perguntando ao dono** o que não dá pra inferir do código (stack,
   comandos exatos, convenções, armadilhas). Nunca invente comando ou regra.
3. Salve na raiz como `CLAUDE.md`. Re-audite até o veredito ficar 🟢.
4. Lembre o dono: revisar o CLAUDE.md quando a stack/comandos mudarem — memória velha engana a IA.

Regra de ouro: **o CLAUDE.md certo é o investimento de token com maior retorno.** Uma vez bem-feito,
ele economiza em cada sessão futura — a IA já chega sabendo do projeto.
