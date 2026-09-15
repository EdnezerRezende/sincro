# Redesign "Direção A" + fluxos de Emergência e Profissionais — Especificação

**Data:** 2026-09-14
**Canvas de referência (17 pranchas, 390×844):** https://claude.ai/artifact/GSMHhPW5JCogkV6T72nv7Y
**Fontes de trabalho do canvas:** `/private/tmp/claude-501/-Users-ed-Desenvolvimento-projetos-sincro/11c78931-0799-413d-8804-a54383950ae1/scratchpad/sincro-design/` (`*.dc.html`, `gen.mjs`, `canvas.json`)

## Decisões fechadas

1. **Direção A "Calmo e claro"** é o sistema adotado. Direção B (tema escuro + barra inferior) fica como protótipo de arquitetura, fora deste ciclo.
2. O tema (`mobile/lib/core/theme.dart`) **não muda**: primária `#005A80`, fundo `#FAF8F5`, raio 16 em cards e 12 em controles, Atkinson Hyperlegible, corpo 16/1.5, escala do tema 12/14/16/20/22 (`headlineSmall` 20, `headlineMedium` 22). Os dois títulos de 24 sp abaixo usam `headlineMedium.copyWith(fontSize: 24)`, sem novo token.
3. **Copy real do app é mantida** em todas as telas existentes. Strings novas só nos dois fluxos novos abaixo.
4. Alvos de toque ≥ 44 dp, contraste AA, botão de emergência sempre alcançável.

## Tela de Login (`/login`)

- Cabeçalho centralizado: logo real (`assets/logos/symbol_transparent_512x512.png`, 96 dp), "Sincro" (`headlineMedium.copyWith(fontSize: 24)`, bold), "Bem-vindo de volta" (`bodyLarge`, `onSurfaceVariant`).
- Remove o tile com emoji `💚`, o gradiente de fundo e as animações de entrada.
- Campos `AppInput` (label flutuante dentro do campo, como já é), checkbox "Lembrar-me neste dispositivo", `AppButton` "Entrar" (large), divisor "OU", "Entrar com Google" (outline), rodapé "Não tem conta? Criar uma conta".

## Home (`/home`, layout `resumo` + estilo `minimalista`)

Somente a combinação `(HomeLayoutMode.resumo, HomeDesignStyle.minimalista)` muda. As outras cinco combinações permanecem.

Ordem vertical, sem rolagem em 390×844 quando há contatos cadastrados; com o aviso de contatos a lista rola, o rodapé de emergência permanece fixo:
1. AppBar existente ("Sincro" + engrenagem).
2. Saudação: "Você está em dia" (`headlineMedium.copyWith(fontSize: 24)`) + "Tudo sob controle" (`bodyMedium`, `onSurfaceVariant`).
3. **Cartão de destaque Finanças**: fundo `primary` a 6 %, borda `primary` a 25 %, linha "Saldo Livre" (ícone + label bold 14), valor em 34 sp bold `primary`, linha "N lançamentos para revisar, sem pressa" + link "Ver finanças →" (44 dp).
4. **Cartão agrupado** (branco, borda `outline`, divisores internos) com três linhas de ~72 dp (título + subtítulo dos cards): Caixa de Entrada, Próximos eventos, Biofeedback (trailing `OutlinedButton` "Ativar Biofeedback" quando inativo).
5. Título "Apoio" (16 bold) + cartão agrupado com duas linhas: Encontrar profissional, Alívio sensorial (subtítulos reais).
6. Rodapé fixo (fora da rolagem): `EmergencyButton` 56 dp + `_NoContactsHint` quando não há contatos.

## Fluxo novo 1 — Avisar Rede de Apoio (folha inferior)

Substitui o `AlertDialog` atual de `EmergencyButton`.

- Título "Avisar Rede de Apoio"; subtítulo "Escolha quem avisar e ajuste a mensagem, se quiser. Nada é enviado sem você confirmar."
- Seção "Quem avisar": lista de contatos de confiança (nome + relação) com checkbox de 44 dp; **todos marcados por padrão**; toque na linha alterna.
- Seção "Mensagem": campo multilinha pré-preenchido com o texto padrão do backend usando o marcador `{primeiro nome}`; contador `N/300`; link "Restaurar padrão"; texto de ajuda "{primeiro nome} vira o nome de cada pessoa".
- Botão primário: `0` marcados → desabilitado, rótulo "Escolha quem avisar"; `1` → "Abrir WhatsApp para <primeiro nome>"; `N` → "Abrir WhatsApp · 1 de N: <primeiro nome>".
- Botão texto "Agora não".
- Rede vazia → SnackBar existente "Cadastre um contato de confiança primeiro." (a folha não abre).
- **Fila de envio**: `wa.me` abre uma conversa por vez. Assim que o WhatsApp é aberto (retorno de `launchUrl`), a folha avança e, quando o usuário volta ao app, mostra "Enviado para <nome>. Próximo: <nome>" e o botão vira "Continuar com <nome>"; ao terminar, fecha com SnackBar "Avisos abertos para N pessoas.".
- Texto editado vale só para a sessão da folha; "Restaurar padrão" volta ao literal do backend.
- **Backend**: `POST /emergency/messages` com `{ contactIds: string[] (1–10, UUID), template?: string (1–300) }` → `[{ contactId, contactName, whatsapp, message, waUrl }]` na ordem enviada; `template` ausente = texto atual; `{primeiro nome}` substituído por contato; contato de outro usuário → 404. `POST /emergency/message` continua funcionando.

## Fluxo novo 2 — Profissionais

### Busca (`/professionals`)
- Campo "Buscar pelo nome" acima dos chips de tag; debounce de 400 ms; busca continua exigindo localização e ordena por distância; com nome digitado, filtra por `nome` contendo o texto (case-insensitive) e mantém a distância.
- Vazio: "Nenhum profissional encontrado por aqui ainda." (já existe).
- **Backend**: `GET /professionals/search?lat&lng&tags&q` — `q` opcional, `contains` insensível a maiúsculas em `nome`.

### Detalhe
- Botão primário "Adicionar à rede de apoio" abaixo de "Abrir WhatsApp"/"Ligar", com nota "Ao adicionar, a pessoa passa a aparecer em Rede de apoio e pode receber seu aviso de emergência."
- Ao tocar: diálogo "Adicionar à rede de apoio" com dropdown "Relação" (padrão derivado das tags: contém "psic" → PSICOLOGO; "psiquiat" → PSIQUIATRA; "t.o" ou "terapeuta ocupacional" → T.O.; senão OUTRO) e checkbox de consentimento (mesmo texto de `add_contact_screen.dart`). Confirmar cria `TrustedContact` com `nome`, `relacao`, `whatsapp = telefone`, `prioridade = 0`, `consentimentoAceito = true`.
- Estados do botão: normal / "Adicionando…" (desabilitado) / "Já está na sua rede de apoio" (desabilitado, quando já existe contato com o mesmo WhatsApp).
- Telefone que não casa com `^\+\d{10,15}$` → botão desabilitado com ajuda "Telefone do profissional em formato inválido."
- SnackBars: "Adicionado à sua rede de apoio." / "Não foi possível adicionar. Tente novamente."

### Admin (`/admin/professionals`, só `isAdmin`)
- Campo "Buscar" (nome, cidade ou tag) filtrando a lista em memória; chip "Mostrar inativos" (desligado por padrão esconde inativos); contagem "N ativos · M inativos".
- Formulário: botão "Usar minha localização atual" preenche latitude/longitude via `LocationService`; permissão negada → mesma mensagem de `mensagemPermissao`.
- Ícone de desativar continua `visibility_off_outlined` (ação reversível); inativos mostram "Reativar" (`PATCH` com `ativo: true` — precisa de suporte no DTO de update).

## Fora de escopo neste ciclo
- Direção B em outras telas; estados de carregamento/vazio/erro redesenhados (mantêm-se os atuais); redesign de Finanças, Caixa de Entrada, Calendário, Biofeedback, Configurações, Alívio sensorial e Rede de apoio (as pranchas confirmam a estrutura atual, sem mudança funcional).

## Emenda 2026-09-15 — Direção A em toda a aplicação

Decisão do produto após ver a release 1.0.11 (2): o redesign restrito a `(resumo, minimalista)` ficou invisível para quem usa outro layout/estilo e as demais telas continuaram no visual antigo. A direção A passa a valer para **toda a aplicação**:

1. **Componentes compartilhados** em `mobile/lib/core/widgets/`: `RowIcon` (tile 40 dp, raio 12, `primary` a 10 %), `SectionRow` (linha 56 dp — 48 dp em `dense` —, título 16 bold, subtítulo 14, chevron quando tocável, `destructive` em `error`), `SectionCard` (ganha `borderColor`), `TonalPanel` (fundo `primary` 6 %, borda 25 %, raio 16, `gradient` opcional) e `StatTile` (rótulo 14 + valor 34 `primary` + unidade 16). Só cores do `ColorScheme` — nada hard-coded —, para os temas claro e escuro.
2. **Home nas seis combinações** (`HomeLayoutMode` × `HomeDesignStyle`): a estrutura é sempre a da prancha "Home · A" — saudação 24/14, cartão de destaque de Finanças, cartão agrupado (Caixa de Entrada, Próximos eventos, Biofeedback), "Apoio" (Encontrar profissional, Alívio sensorial) e rodapé fixo com `EmergencyButton`. O que muda por estilo:
   - *Minimalista Refinado*: a prancha ao pé da letra (tonal chapado, respiro generoso).
   - *Moderno Suave*: mesma malha com degradê sutil `primary → secondary` nos tiles e no cartão de destaque; acentos por linha vindos do esquema (`secondary`, `tertiary`), nunca de `Colors.*`.
   - *Funcional Direto*: linhas densas (48 dp, ícone simples), borda forte (`#9C9690` claro / `#66605A` escuro, ≥ 2,5:1), títulos em todos os grupos ("Hoje", "Apoio"), linha "Status do dia", subtítulos só com o dado (ex.: o e-mail, sem "Conectado como") e check verde nos itens conectados/ativos. O cartão de destaque é mais compacto (valor em 28 sp).
   - *Abas*: saudação + cartão de destaque fixos acima de "Hoje" / "Apoio"; as abas mostram os mesmos cartões agrupados; emergência fixa fora do `TabBarView`.
   - "Ver finanças" é um link inline dentro do cartão tocável (não um botão), para não criar um segundo nó de acessibilidade dentro do `Semantics` do cartão.
3. **Configurações** (prancha "Configurações"): grupos em `SectionCard` com título 16 bold — Perfil & Preferências, Conexões, Biofeedback (se ativo), Administração (admin), Ajuda, Conta — e o **valor atual como subtítulo** de cada linha (layout, estilo, tema, "N contatos", "Conectado como …", "Dia N de cada mês", "A cada 30 minutos"). Ações destrutivas em `error`. Novo `biofeedbackFrequenciaProvider`.
4. **Demais telas**: Biofeedback (dois `StatTile` lado a lado + `TonalPanel` com estado atual e horário), Rede de apoio (contatos em `SectionCard`, atalho "Buscar profissional cadastrado · Pelo nome ou perto de você" → `/professionals`, "Adicionar contato" como botão de 56 dp no rodapé em vez de FAB), Alívio sensorial (Favoritos e "Todos os cartões" em `SectionCard`, ícone por categoria), Finanças ("Saldo Livre" em `TonalPanel`, mesmo chrome da Home), Caixa de Entrada (título de grupo 16 bold e margem 20 dp; os tiles com faixa âmbar de atenção são mantidos por acessibilidade).
5. **Fora desta rodada**: Calendário (estrutura já confere com a prancha; 1 300 linhas, fica para rodada própria), Criar conta (já bate com a prancha), Direção B. **Sugestão da crítica, pendente de decisão de produto**: a tela de Biofeedback termina em ~266 dp de 844; uma faixa de tendência de 7 dias (FC/VFC em repouso, a partir de `BiofeedbackCache.getHistoricoRepouso()`) preencheria o vazio, mas não está na prancha.
6. **Exceções de cor literal** (únicos `Color(0x…)` fora do `ColorScheme`, todos bordas calibradas por contraste ≥ 2,5:1 contra o fundo, que `outline` não atinge): `_kBorderLight/_kBorderDark` em `home_screen.dart` (estilo Funcional) e em `inbox_screen.dart` (borda dos tiles de e-mail, pré-existente, `#7C7672` nos dois temas). Qualquer outra cor literal em widget novo é regressão.
7. **Selo compacto do `trailing`** ("Ativar / Biofeedback", "Conectar / Gmail"): largura máxima 112 dp × escala de texto (a palavra mais longa, "Biofeedback", mede 84,5 dp em 14/700 Atkinson), padding 8/6, mínimo 44 dp de altura × escala; nunca quebra a própria palavra — o teste confere que cada linha renderizada é uma palavra inteira do rótulo, com no máximo duas linhas, nos dois layouts, nos dois temas, em 1,0× e 1,3×.
   **Cartão de destaque de Finanças**: a linha de apoio abaixo do valor está sempre presente — "N lançamentos para revisar, sem pressa", "Tudo revisado por aqui" (zero) ou "Seus lançamentos do mês, sem pressa" (contagem indisponível) — e o valor encolhe (`FittedBox`) em vez de quebrar o número em texto grande; o mesmo vale para o valor do `StatTile`.
   **Biofeedback**: os dois `StatTile` ficam lado a lado (mesma altura) até 1,5× de texto e empilham a partir daí, para o rótulo não quebrar no meio da palavra; o horário da última atualização é sempre 24 h (`HH:mm`, "08:40"), independente do relógio do aparelho. **Rede de apoio**: os três botões do rodapé ("Adicionar contato", "Continuar", "Pular por enquanto") têm 56 dp.
8. **Testes**: `home_direcao_a_combinacoes_test.dart` (6 combinações × claro/escuro, emergência visível sem rolar em 390×844), `settings_screen_test.dart` (grupos, subtítulos, tema escuro, diálogo). As 8 falhas em `app_chip*_test.dart` são pré-existentes.

### Itens abertos registrados pela crítica final (2026-09-15, rodada 6 — APPROVED)
Nenhum é regra da Emenda nem está nos arquivos alterados; ficam para decisão:
1. Título das AppBars: pranchas usam 22/700; o tema aplica `titleLarge` 22/400 (`appBarTheme.titleTextStyle` nulo) — mudança global de uma linha em `core/theme.dart`.
2. "Adicionar contato" na Rede de apoio é `OutlinedButton` de largura cheia; a prancha mostra botão preenchido mais estreito à direita (a largura cheia foi exigida pela crítica; o preenchimento é hierarquia).
3. Copy do Biofeedback: prancha diz "Atualizado hoje às 08:40"; o app omite "hoje" no mesmo dia (mantém "ontem"/"em dd/mm").
4. Faixa de tendência de 7 dias no Biofeedback (fora da prancha; ver item 5).
5. O "—" de VFC ausente em 34 sp `primary` lê como barra sólida no escuro; `onSurfaceVariant` seria mais neutro.
