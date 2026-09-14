# Onde o token vaza — e como sair do buraco

Todo build com IA que "queima a assinatura" cai num punhado de padrões. Reconhecer o padrão é metade
da cura. Registre suas sessões (`sessao-iniciar`/`sessao-fechar`) e o `stats` vai te mostrar quais
desses mais te pegam.

## Os padrões que queimam token

### 1. Jogar o repositório inteiro no contexto
O clássico. A tarefa toca 4 arquivos, mas a IA está lendo 80. Cada mensagem paga por todos.
→ **Saída:** raio-x com a tarefa, abra só o conjunto enxuto, use `.claudeignore`. (Ver `contexto.md`.)

### 2. Construir sem plano ("só faz aí")
Sem alvo, a IA preenche o vazio adivinhando, entrega o que você não pediu, e você refaz — pagando
duas vezes.
→ **Saída:** plano curto antes (objetivo, arquivos, passos, aceite, fora-de-escopo). (Ver `planejar.md`.)

### 3. A IA em loop (mesma correção, de novo e de novo)
Ela tenta, não resolve, tenta parecido, não resolve — e o histórico (que você paga) só cresce.
→ **Saída:** pare. Se a mesma coisa falhou ~3 vezes, o problema não é o que ela está tentando — é o
   entendimento. Volte um passo, releia o erro real, e se for um bug quebrado, use o **Rastro**
   (depuração metódica). Não deixe a IA "tentar mais uma".

### 4. Refazer tudo em vez do menor pedaço
Pedir "reescreve esse arquivo" quando bastava mudar 3 linhas. A IA regenera 200 linhas, introduz
regressão, e você revisa tudo.
→ **Saída:** peça a **menor mudança que resolve** — "só o diff", "só a função X".

### 5. Não ter CLAUDE.md (a IA redescobre o projeto toda sessão)
Toda conversa ela pergunta/adivinha a stack, os comandos, a estrutura — de novo.
→ **Saída:** um CLAUDE.md enxuto e certeiro. (Ver `claude_md.md`.) É o poupador nº1.

### 6. Arrastar a conversa antiga pra tarefa nova
Você terminou a feature A e emenda a feature B na mesma conversa. Todo o contexto de A vira token
morto pagando junto em B.
→ **Saída:** `/clear` ao trocar de tarefa. Uma tarefa, uma conversa.

### 7. Pedir explicação quando você quer código
Parágrafos que você não vai ler são token gasto.
→ **Saída:** "saída: só o código". Peça explicação só quando for entender.

## O protocolo de resgate (quando já está queimando)
1. **Pare de mandar "tenta de novo".** Cada tentativa cega custa e piora o histórico.
2. **`/clear`** e recomece a tarefa limpa, com só os arquivos-alvo.
3. **Releia o pedido:** tinha objetivo, arquivos fixos, aceite e "não faça"? Se não, é por isso.
4. **Quebre menor:** se a tarefa era grande, divida em dois planos.
5. **Regra das 3 quedas:** falhou 3 vezes seguidas → não é a correção, é o entendimento ou a
   arquitetura. Pare a IA, pense você, e só volte com um alvo novo e menor.

## O painel te mostra o padrão
```
python3 scripts/prumo.py stats
```
Ele conta quantas sessões **travaram** ou entraram em **loop**, quanto token queimou, e **quais
assuntos mais dão problema**. Assunto que repete no vermelho = ou falta um CLAUDE.md melhor pra ele,
ou a tarefa precisa vir mais enxuta. O dado aponta onde apertar o prumo.

Economia de token não é um truque — é disciplina repetida: **plano curto, contexto pequeno, um passo
por vez, e parar antes do loop.**
