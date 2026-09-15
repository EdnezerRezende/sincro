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

Ordem vertical, sem rolagem em 390×844:
1. AppBar existente ("Sincro" + engrenagem).
2. Saudação: "Você está em dia" (`headlineMedium.copyWith(fontSize: 24)`) + "Tudo sob controle" (`bodyMedium`, `onSurfaceVariant`).
3. **Cartão de destaque Finanças**: fundo `primary` a 6 %, borda `primary` a 25 %, linha "Saldo Livre" (ícone + label bold 14), valor em 34 sp bold `primary`, linha "N lançamentos para revisar, sem pressa" + link "Ver finanças →" (44 dp).
4. **Cartão agrupado** (branco, borda `outline`, divisores internos) com três linhas de 56 dp: Caixa de Entrada, Próximos eventos, Biofeedback (trailing `OutlinedButton` "Ativar Biofeedback" quando inativo).
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
