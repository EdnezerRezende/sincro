# Contexto & tokens — abra só o que precisa

Contexto é tudo que a IA "está lendo" numa sessão: os arquivos abertos, o CLAUDE.md, o histórico da
conversa. **Cada coisa nele custa token, em toda mensagem.** A regra do Prumo é simples: **o menor
contexto que resolve a tarefa.** Não é sobre a IA saber pouco — é sobre ela ler só o que importa.

## O maior desperdício: jogar o repositório inteiro
Abrir "o projeto todo" pra IA parece produtivo, mas é o buraco por onde a assinatura vaza. Um projeto
médio tem dezenas de milhares de tokens de código; a tarefa quase sempre toca 3-6 arquivos. Ler o
resto é dinheiro fora.

Use o **raio-x** pra ver o peso e escolher o conjunto enxuto:
```
python3 scripts/prumo.py raiox                              # peso total + pastas/arquivos mais pesados
python3 scripts/prumo.py raiox --tarefa "corrigir o login" --top 6
```
O raio-x sugere os arquivos que casam com a tarefa (por nome e por conteúdo). **Abra só esses.**
Eles viram os `arquivos-alvo` do plano.

## `.claudeignore` — esconda o peso morto
Crie um arquivo `.claudeignore` na raiz do projeto (igual a um `.gitignore`) listando o que a IA
**nunca** precisa ler. Isso tira dependências, builds e dados gigantes do caminho:
```
# .claudeignore — o que a IA não precisa ler
node_modules/
.venv/
venv/
dist/
build/
out/
coverage/
*.min.js
*.min.css
*.lock
data/
*.csv
*.sqlite
.next/
```
Ajuste ao seu projeto. Peso morto fora do contexto = mais token pro que importa.

## Quando limpar a conversa: /clear vs /compact
O histórico da conversa também é contexto que cresce e custa.
- **`/clear`** — zera a conversa. Use quando **terminar uma tarefa** e for começar OUTRA sem relação.
  Não arraste o contexto da tarefa antiga pra nova — é token puro desperdiçado.
- **`/compact`** — resume a conversa longa mantendo o essencial. Use no **meio de uma tarefa longa**
  que já ficou pesada, mas que você ainda precisa continuar.
- Regra prática: **uma tarefa, uma conversa.** Fechou a tarefa, `/clear`. Isso sozinho corta muito gasto.

## Peça a saída no tamanho certo
Você controla quanto a IA escreve:
- Quando quer **só o código**, diga "só o código, sem explicação". Explicação longa que você não vai
  ler é token gasto.
- Quando quer entender, aí sim peça a explicação. O ponto é **escolher** — não receber parágrafos por
  padrão.

## Agrupe tarefas relacionadas (reúso de contexto)
Se três coisas mexem nos mesmos arquivos, faça na **mesma conversa**, em sequência — a IA já tem o
contexto carregado e você não paga pra recarregar. Mas assim que o assunto mudar de verdade, `/clear`.

## Checklist rápido de contexto enxuto
- [ ] Rodei o raio-x e sei os 3-6 arquivos que a tarefa toca.
- [ ] Tenho um `.claudeignore` tirando node_modules/dist/dados do caminho.
- [ ] Não estou com o repositório inteiro aberto "por via das dúvidas".
- [ ] Fechei a tarefa anterior com `/clear` antes de começar esta.
- [ ] Pedi a saída no tamanho certo (código só, quando é só código).
- [ ] Meu CLAUDE.md está enxuto (veja `claude_md.md`) — ele entra em TODA sessão.

Contexto pequeno não é a IA saber menos. É ela **ler só o necessário** — e você pagar só por isso.
