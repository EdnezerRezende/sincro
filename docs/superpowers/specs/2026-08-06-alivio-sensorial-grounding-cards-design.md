# Sincro — Comunidade & Alívio Sensorial: Grounding Cards (Fase 1 deste pilar)

## Contexto

O Sincro é um app voltado para adultos autistas nível 1 de suporte, com foco em reduzir a carga
executiva e a ansiedade do dia a dia. Onboarding/Anamnese/Rede de Apoio, Gestão Executiva —
Triagem de E-mail, Finanças Generativas, Biofeedback & Crise (3 fases) e Conexão Profissional
estão implementados e revisados. O spec original
(`docs/superpowers/specs/2026-08-01-onboarding-anamnese-rede-apoio-design.md`) lista "Comunidade &
Alívio Sensorial" como o último dos cinco próximos sub-projetos, com o escopo "grounding cards,
peer support, conteúdo validado pela comunidade".

Esse escopo original mistura pelo menos três subsistemas independentes: uma biblioteca de
conteúdo curado (grounding cards), interação usuário-a-usuário (peer support) e um mecanismo de
curadoria coletiva sobre esse conteúdo. Peer support em particular exige moderação e políticas de
segurança/privacidade bem mais pesadas — especialmente considerando que o público deste app é
uma população que merece cuidado redobrado nesse tipo de superfície — e não faz sentido antes de
existir conteúdo para as pessoas interagirem em torno dele. Este documento cobre só a primeira
fatia: a biblioteca de grounding cards. Peer support e validação comunitária ficam para fases
futuras deste mesmo pilar, cada uma com seu próprio ciclo spec → plano → implementação.

## Objetivo desta fase

Ao final desta fase, o usuário deve poder:

1. Abrir a biblioteca de grounding cards a partir de um novo card na Home.
2. Ver os cards favoritados numa seção no topo da tela (se houver algum), seguidos da lista
   completa, filtrável por categoria (Respiração, Aterramento Sensorial, Movimento/Alongamento,
   Atenção Plena, Outro).
3. Abrir um card e ver o passo a passo completo em texto.
4. Favoritar/desfavoritar um card a partir da tela de detalhe.

A equipe Sincro (conta com `isAdmin = true`) deve poder:

5. Cadastrar, editar e desativar grounding cards, por uma tela dentro do próprio app Flutter —
   mesmo padrão já usado pelo diretório de profissionais da Conexão Profissional.

## Fora de escopo

- **Peer support** (fórum, chat, grupos entre usuários) — subsistema independente, maior escopo,
  com necessidades de moderação e segurança que exigem seu próprio ciclo de design. Fica para uma
  fase futura deste pilar.
- **Conteúdo validado pela comunidade** (votação, curadoria coletiva sobre os cards) — só faz
  sentido depois de existir conteúdo e/ou comunidade para validar; fica para uma fase futura.
- **Imagem, áudio ou vídeo nos cards.** Só texto nesta fase — mantém o cadastro admin rápido e a
  experiência leve, consistente com o tom calmo do app (mesma decisão já tomada para os campos
  essenciais da Conexão Profissional).
- **Sugestão contextual a partir do Biofeedback** (ex.: sugerir uma card quando o estado de
  estresse fica "elevado"). A biblioteca é uma seção autônoma, navegável a qualquer momento pelo
  usuário — não acoplada a nenhum outro pilar nesta fase.
- **Categorias livres/customizáveis pelo admin.** O conjunto de categorias é fixo e pré-definido
  (ver Arquitetura); evita inconsistência de digitação e mantém o filtro da tela do usuário
  previsível.
- **Histórico de uso ou analytics de quais cards o usuário abriu/usou** — só a lista de favoritos
  é persistida.

## Arquitetura

### Modelo de dados (backend)

Novo model Prisma `GroundingCard` (`@@map("cartoes_aterramento")`):

- `id`, `titulo`, `categoria` (`String`, um dos valores fixos `RESPIRACAO`,
  `ATERRAMENTO_SENSORIAL`, `MOVIMENTO`, `ATENCAO_PLENA`, `OUTRO` — mesmo padrão de enum-como-string
  já usado em `TrustedContact.relacao`), `conteudo` (texto do passo a passo), `ativo` (`Boolean`,
  default `true` — soft-delete), `criadoEm`/`atualizadoEm`.

Novo model Prisma `CardFavorito` (`@@map("cartoes_favoritos")`), relação usuário-card:

- `id`, `userId`, `cardId`, `criadoEm`, com `@@unique([userId, cardId])` e `@@index([userId])` —
  mesmo padrão relacional de `TrustedContact`.

### API (backend)

- `GET /grounding-cards` — autenticado via Firebase, retorna cards `ativo=true`; aceita
  `?categoria=` opcional para filtrar por uma das categorias fixas.
- `GET /grounding-cards/favoritos` — lista os cards favoritados pelo usuário autenticado
  (resolvido via `UsersService.getByFirebaseUidOrThrow`, nunca por um id vindo do cliente).
- `POST /grounding-cards/:id/favoritar` — marca o card como favorito do usuário autenticado
  (idempotente: favoritar um card já favoritado não duplica, respeitando o `@@unique`).
- `DELETE /grounding-cards/:id/favoritar` — remove o favorito.
- `GET/POST/PATCH/DELETE /admin/grounding-cards[...]` — protegidos por `FirebaseAuthGuard` +
  `AdminGuard` (guard já existente, criado na Conexão Profissional). `GET` lista todos os cards
  incluindo inativos; `DELETE` é soft-delete (seta `ativo=false`), nunca remove a linha.

### Mobile: UI

- **Home:** novo card "🌿 Alívio sensorial" → tela da biblioteca.
- **Tela da biblioteca:**
  - Seção "Favoritos" no topo, visível só quando o usuário tem ao menos um card favoritado.
  - Abaixo, lista completa agrupada/filtrável por categoria (chips, mesmo padrão de filtro já
    usado na busca de profissionais da Conexão Profissional).
  - Lista vazia (nenhum card cadastrado ainda, ou filtro sem resultado): mensagem neutra, sem
    parecer erro — mesmo tom do resto do app.
- **Tela de detalhe:** título, categoria, passo a passo completo, botão de favoritar/desfavoritar
  (ícone de coração). Atualização otimista da UI ao tocar, com rollback e aviso calmo se a chamada
  de rede falhar.
- **Tela admin** (`/admin/grounding-cards`, visível só quando `isAdmin === true`, mesmo gate já
  usado para o diretório de profissionais em Configurações): lista completa (incluindo inativos) +
  formulário de criar/editar (título, categoria via dropdown fixo, conteúdo) + ação de desativar
  com confirmação.

### Erros

- Falha de rede ao carregar a biblioteca ou os favoritos: estado calmo "não foi possível carregar
  agora" com opção de tentar novamente, sem retry automático agressivo.
- Falha ao favoritar/desfavoritar: a UI reverte para o estado anterior e mostra um aviso curto,
  sem bloquear a navegação.

## Segurança e Privacidade

- Todos os endpoints exigem autenticação Firebase, como o resto do backend.
- Endpoints admin adicionalmente exigem `isAdmin === true`, resolvido do token verificado — nunca
  de um valor enviado pelo cliente.
- Favoritos são sempre escopados ao usuário autenticado (resolvido via
  `UsersService.getByFirebaseUidOrThrow`), nunca por um `userId` vindo do cliente — mesma regra de
  tenant isolation já aplicada em todos os pilares anteriores.
- Conteúdo dos cards é informação pública/curada pela Sincro, não dado sensível do usuário.

## Testes

- **Backend:**
  - Filtro por categoria e listagem de cards ativos, com dados de teste.
  - Favoritar/desfavoritar: idempotência (favoritar duas vezes não duplica), escopo por usuário
    (favoritos de um usuário não vazam para outro), remoção correta.
  - Guard admin: acesso permitido para `isAdmin=true`, 403 para `isAdmin=false` e para não
    autenticado — reaproveitando o `AdminGuard` já testado na Conexão Profissional.
  - CRUD admin: criar/editar/desativar card, e que a desativação é soft (registro continua no
    banco com `ativo=false`, some da listagem pública, continua na listagem admin).
- **Mobile:** repositórios testados via interceptor do Dio (mesmo padrão de
  `professionals_repository_test.dart`); nenhuma tela ganha teste de widget (`pumpWidget`) —
  mesma convenção de testes já estabelecida e documentada na Conexão Profissional, já que este
  código base nunca teve testes desse tipo. A UI é coberta por verificação manual.
- **Verificação manual:** favoritar/desfavoritar de fato persiste entre reaberturas do app; a
  seção de favoritos desaparece corretamente quando o último favorito é removido; conta
  não-admin não vê a entrada da tela admin em Configurações.
