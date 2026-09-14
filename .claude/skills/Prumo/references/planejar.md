# Planejar — o plano curto que salva a assinatura

O maior gasto de token não é o código: é a IA **construindo sem alvo**. Ela chuta, mexe em coisa
demais, refaz, e você paga por cada volta. Um plano de 5 minutos corta isso. Este é o método.

## Por que planejar economiza (não é burocracia)
- Sem plano, a IA **preenche o vazio adivinhando** → gera coisa que você não pediu → você refaz.
- Com um alvo escrito, ela vai reto ao ponto e você verifica em vez de re-explicar.
- O plano cabe numa página. É rápido. E é reutilizável (o próximo build parecido copia a estrutura).

## As 5 partes de um plano enxuto
Toda tarefa de build vira isto (o motor guarda tudo em `.prumo/planos/<slug>.json`):

1. **Objetivo** — o quê e por quê, em 1-2 frases. "Usuário não loga com e-mail em maiúsculo; quero
   que funcione em qualquer caixa." Concreto, não "melhorar o login".
2. **Arquivos-alvo** — o **conjunto enxuto** de arquivos que a tarefa vai tocar. Saem do raio-x
   (`raiox --tarefa`). Isso é o contexto que a IA vai abrir — quanto menor e mais certo, mais barato.
3. **Passos verificáveis** — em 3 fases, cada passo com **como saber que deu certo**:
   - **1. Preparar** — reproduzir, entender, criar o teste/andaime.
   - **2. Construir** — a mudança em si, o menor pedaço que resolve.
   - **3. Testar e verificar** — rodar, conferir verde, revisar.
   Cada passo é **verbo + o quê + qual arquivo** ("Normalizar o e-mail com toLowerCase em `src/api/auth.ts`"),
   nunca vago ("melhorar o código").
4. **Critério de aceite** — a frase que define "terminou": "login funciona com e-mail em qualquer
   caixa e o teste passa". Sem isso, não dá pra saber quando parar (e a IA fica mexendo à toa).
5. **Fora de escopo** — o que NÃO fazer agora. "Não mexer no checkout, não refatorar o CSS." Essa
   linha é a que mais economiza: ela **trava a IA de sair passeando** por outras partes do projeto.

## Como conduzir a conversa (você, a IA)
1. Ouça o pedido do dono. Se estiver vago, faça **2-3 perguntas** (o quê exatamente, onde no sistema,
   como fica "pronto"). Nunca invente detalhe que ele não deu.
2. Rode o raio-x com as palavras da tarefa pra achar os arquivos-alvo.
3. Escreva o plano com os comandos do motor. Mostre o plano montado pro dono confirmar **antes** de
   qualquer código.
4. Só então caminhe passo a passo.

### Comandos
```
python3 scripts/prumo.py plano-nova --titulo "Corrigir login case-insensitive" \
   --objetivo "Usuário não loga com e-mail em maiúsculo; funcionar em qualquer caixa" \
   --aceite "Login entra com e-mail em qualquer caixa e o teste passa" \
   --fora "mexer no checkout; refatorar CSS"
python3 scripts/prumo.py plano-alvo --slug corrigir-login-case-insensitive --add "src/api/auth.ts,tests/auth.test.ts"
python3 scripts/prumo.py passo-add --slug corrigir-login-case-insensitive --fase setup \
   --texto "Escrever um teste que reproduz o bug com e-mail maiúsculo" --arquivo "tests/auth.test.ts" \
   --aceite "o teste FALHA antes da correção"
python3 scripts/prumo.py passo-add --slug corrigir-login-case-insensitive --fase impl \
   --texto "Normalizar o e-mail com toLowerCase antes de comparar" --arquivo "src/api/auth.ts"
python3 scripts/prumo.py passo-add --slug corrigir-login-case-insensitive --fase teste \
   --texto "Rodar a suíte e conferir verde" --aceite "npm test passa"
python3 scripts/prumo.py plano --slug corrigir-login-case-insensitive
```

## Caminhar passo a passo (modo 3)
Depois do plano pronto e do pré-voo 🟢, construa **um passo por vez**:
```
python3 scripts/prumo.py passo-proximo --slug <slug>     # mostra SÓ o próximo + como verificar
# ... você/a IA faz esse passo, e SÓ esse, usando só os arquivos-alvo ...
# ... verifica o aceite (roda o teste, confere) ...
python3 scripts/prumo.py passo-concluir --slug <slug> --id N
```
Por que um por vez: se a IA faz 5 coisas de uma vez e uma quebra, você não sabe qual — e refaz tudo
(token queimado). Um passo verificado por vez mantém o build no prumo.

## Erros comuns (evite)
- **Plano gigante.** Se passou de ~7 passos ou ~12 arquivos-alvo, a tarefa é grande demais: quebre em
  dois planos. Contexto grande = token e confusão.
- **Passo vago.** "Melhorar", "ajustar", "organizar" não são passos. Diga o verbo, o quê e o arquivo.
- **Sem fora-de-escopo.** É a trava mais barata contra a IA passear. Sempre declare.
- **Pular o aceite.** Sem "como saber que terminou", a sessão não fecha e o token vaza.
