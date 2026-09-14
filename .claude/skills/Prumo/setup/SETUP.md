# Setup de primeira execução do Prumo

> Você (a IA) está lendo isto porque **não existe `.prumo/config.md` na raiz do projeto**. Conduza
> este setup UMA vez, em conversa PT-BR, e depois se autodestrua. Se `.prumo/config.md` já existir,
> NÃO rode o setup — vá direto para os modos do SKILL.md.

## O que fazer

### 1. Converse (curto, amigável, sem jargão)
Pergunte ao dono, uma de cada vez (aceite respostas curtas; nada é obrigatório além do nome):

1. **Como você quer ser chamado?** (ex.: Fabio)
2. **Qual o nome do projeto que você está construindo?** (ex.: meu-ERP, site da clínica)
3. **Qual a stack?** — linguagem/framework/banco. (ex.: Node + React + TypeScript + PostgreSQL)
   Se não souber dizer, tudo bem: escreva "a descobrir".
4. **Como o projeto roda e testa?** — os comandos, se ele souber. (ex.: `npm run dev`, `npm test`)
   Se não souber, deixe "a definir" — o Prumo ajuda a descobrir depois.
5. **Seu nível com código?** (1 = quase nada, faço tudo pela IA · 2 = me viro · 3 = sou dev)
   Isso só ajusta o quanto o Prumo explica.

Não invente respostas. Se o dono não sabe, registre "a definir".

### 2. Grave a config
Crie o arquivo **`.prumo/config.md`** na **raiz do projeto** (não dentro da skill) com este formato
exato (mantenha os `**` e os acentos):

```markdown
# Config do Prumo

- **Nome:** [nome do dono]
- **Projeto:** [nome do projeto]
- **Stack:** [linguagem/framework/banco, ou "a descobrir"]
- **Comando de rodar:** [ex.: npm run dev, ou "a definir"]
- **Comando de testar:** [ex.: npm test, ou "a definir"]
- **Nível técnico:** [1, 2 ou 3]
- **Criado em:** [data de hoje YYYY-MM-DD]
```

### 3. Garanta o `.gitignore`
A pasta `.prumo/` guarda planos e o diário de sessões do dono — **não deve ir pro Git**. Cheque se a
raiz do projeto tem um `.gitignore` com a linha `.prumo/`; se não tiver, acrescente:
```
.prumo/
```
(Se o projeto não usa Git, ignore este passo.)

### 4. Ofereça o CLAUDE.md (grande oportunidade de economia)
Pergunte: **"Seu projeto já tem um arquivo CLAUDE.md na raiz?"**
- Se **sim**: rode `python3 scripts/prumo.py claudemd-auditar` e mostre o que dá pra melhorar.
- Se **não**: explique em uma frase que o CLAUDE.md é a memória do projeto que economiza token toda
  sessão, e ofereça gerar um esqueleto agora com `python3 scripts/prumo.py claudemd-modelo`
  (preencha com o dono). Não force — ofereça.

### 5. Confirme e mostre o caminho
Diga algo como:
> "Pronto, [Nome]! O Prumo está configurado pro projeto **[Projeto]**. Sempre que for construir ou
> mexer em algo, me chame: eu monto um plano enxuto, descubro os poucos arquivos que importam, e a
> gente constrói um passo por vez — pra acertar na primeira e não queimar token. Quer começar por
> uma tarefa agora ou arrumar o CLAUDE.md do projeto?"

Liste os 6 modos em uma linha cada (Planejar, Contexto/raio-x, Passo a passo, Memória do projeto,
Pré-voo, Painel & Economia).

### 6. AUTODESTRUA o setup
Depois de gravar `.prumo/config.md`, **apague a pasta `setup/` inteira** da skill para o Prumo ficar
limpo:
```
rm -rf setup
```
(Rode isso a partir da pasta da skill `prumo/`. Se tiver dúvida do caminho, apague a subpasta `setup/`
que fica ao lado de `SKILL.md`.)

Feito isso, o setup nunca mais roda — nas próximas vezes o Prumo vê o `.prumo/config.md` e vai direto
ao trabalho.
