# Pedir o build em formato enxuto

Como você pede é metade da economia. Um pedido vago faz a IA adivinhar e produzir demais; um pedido
estruturado vai reto ao alvo. Não é sobre prompt "mágico" — é sobre dar o alvo, o contexto e o
critério de pronto de uma vez.

## O formato do pedido de build
Depois de ter o plano e os arquivos-alvo, peça assim (adapte, não é fórmula rígida):

```
Tarefa:   [o passo específico do plano — um só]
Arquivos: [os arquivos-alvo — abra e mexa SÓ nesses]
Stack:    [o que o CLAUDE.md já diz; repita se necessário]
Regras:   [as convenções que importam pra este passo]
Aceite:   [como saber que ficou pronto — o teste/comportamento]
Saída:    [código só / com explicação curta]
```

Exemplo:
```
Tarefa:   Normalizar o e-mail com toLowerCase antes de comparar no login.
Arquivos: src/api/auth.ts  (e o teste em tests/auth.test.ts)
Regras:   função pequena, sem mudar a assinatura pública; manter o estilo do arquivo.
Aceite:   login entra com e-mail em qualquer caixa e `npm test` passa.
Saída:    só o diff dos dois arquivos.
```

## Requisitos em camadas (quando a tarefa é maior)
Se o pedido tem partes de prioridade diferente, separe — a IA foca no essencial primeiro:
```
Essencial (tem que ter):  [o núcleo que resolve]
Depois (se sobrar):       [o desejável]
Estilo/UX:                [aparência, se aplica]
Não faça:                 [o fora-de-escopo do plano]
```

## Um pedido, um passo
Não empilhe "faz isso, e aquilo, e mais aquilo" num pedido só. Isso é o que faz a IA construir demais
e você não saber o que quebrou. **Um passo do plano por pedido.** Faz, verifica, próximo.

## Peça pra pensar antes de escrever muito (nas tarefas difíceis)
Numa tarefa que você não tem certeza, peça primeiro **o plano de ataque em 3 linhas**, aprove, e só
então mande escrever. Bem mais barato do que ela escrever 200 linhas na direção errada e refazer.
(No Claude Code, o "plan mode" faz exatamente isso.)

## Sinais de que o pedido estava ruim (e queimou token)
- A IA entregou muito mais do que você pediu → faltou "não faça" e "saída".
- Ela mexeu em arquivos que você não citou → faltou fixar os arquivos-alvo.
- Você teve que dizer "não era isso" 3 vezes → faltou o critério de aceite no pedido.
- Ela escreveu três parágrafos e você só queria o código → faltou dizer "saída: código só".

Cada um desses vira uma regra pro próximo pedido. Pedido enxuto → resposta no alvo → token no lugar certo.
