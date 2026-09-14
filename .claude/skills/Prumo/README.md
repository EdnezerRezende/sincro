# Prumo 🧭📐

**Construa software com o Claude Code "no prumo": plano enxuto, contexto pequeno, um passo por vez —
pra acertar na primeira e não queimar a assinatura em tokens.**

O fio de prumo é a ferramenta simples que mantém a parede reta. O Prumo faz o mesmo com quem constrói
software usando IA: mantém o trabalho reto e verdadeiro **antes** e **durante** o build — que é onde a
maioria dos tokens vaza.

É a peça que faltava do lado de quem constrói com IA:
- **Estaleiro** escreve o código · **Rastro** depura o bug · **Prumo** planeja o build e segura o token.

## O que ele faz (6 modos)

| Modo | Pra quê |
|------|---------|
| **Planejar** | Vira o pedido vago num plano curto: objetivo, arquivos-alvo, passos verificáveis, aceite e fora-de-escopo. |
| **Contexto (raio-x)** | Mede o peso do projeto e diz **quais poucos arquivos** abrir pra tarefa — em vez do repositório todo. |
| **Passo a passo** | Caminha o plano **um passo verificável por vez** — o ritmo que não deixa a IA se perder. |
| **Memória do projeto** | Audita/gera o **CLAUDE.md** (a memória lida toda sessão) — o maior poupador de token. |
| **Pré-voo** | Porta antes de soltar a IA: tem plano? contexto enxuto? aceite? → 🟢/🟡/🔴. |
| **Painel & Economia** | Diário de sessões que mostra **onde o token vaza** (o que trava, o que dá loop). |

## Instalar

1. Baixe e descompacte o `Prumo.zip`.
2. Copie a pasta `Prumo/` para dentro do seu projeto, em `.claude/skills/`:
   ```
   seu-projeto/.claude/skills/Prumo/
   ```
   (ou para `~/.claude/skills/Prumo/` para ativá-la em todos os seus projetos).
3. Abra o Claude Code **dentro do seu projeto** e diga, por exemplo:
   *"Vou construir uma feature nesse projeto, me ajuda a planejar sem queimar token."*
   O Prumo dispara sozinho. Na primeira vez ele faz um setup rápido (nome, projeto, stack).

## Como se usa (você só conversa)
Você não digita comando nenhum — fala em português e a IA cuida do resto. Exemplos:
- *"Preciso adicionar login com Google nesse sistema — por onde começo?"*
- *"Quais arquivos eu abro pra mexer no checkout?"*
- *"Monta/arruma o CLAUDE.md do meu projeto."*
- *"A IA fica em loop e gasta token — me ajuda a organizar antes."*
- *"Me mostra onde meu token está indo embora."*

## Regras de ouro
- Plano antes de código · Contexto enxuto (nunca o repo todo) · Um passo verificável por vez.
- Nunca inventa (pergunta) · Mede, não acha · A IA sugere, você aprova e roda.
- **Tudo é local**, numa pasta `.prumo/` dentro do seu projeto. Nada vai pra internet, nenhuma chave, nenhuma senha.

## Requisitos
- **Claude Code** e **Python 3** (já vem no macOS e na maioria dos Linux). Nada mais — sem instalar
  bibliotecas, sem conta, sem API.

## Privacidade
100% offline. Seus planos, sessões e config ficam só no seu computador, em `.prumo/`. O Prumo não
envia nada para lugar nenhum.

---

Feito com carinho para a comunidade **Maestros da IA**. Licença MIT.
