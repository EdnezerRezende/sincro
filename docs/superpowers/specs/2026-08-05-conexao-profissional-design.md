# Sincro — Conexão Profissional

## Contexto

O Sincro é um app voltado para adultos autistas nível 1 de suporte, com foco em reduzir a carga
executiva e a ansiedade do dia a dia. Onboarding/Anamnese/Rede de Apoio, Gestão Executiva —
Triagem de E-mail, Finanças Generativas e o pilar Biofeedback & Crise (3 fases) estão implementados
e revisados. O spec original
(`docs/superpowers/specs/2026-08-01-onboarding-anamnese-rede-apoio-design.md`) lista "Conexão
Profissional" como um dos próximos sub-projetos: busca/recomendação geolocalizada de profissionais
de saúde mental neuroafirmativos.

## Objetivo

Ao final deste pilar, o usuário deve poder:

1. Abrir a busca de profissionais a partir de um novo card na Home.
2. Conceder permissão de localização e ver uma lista de profissionais próximos, ordenada por
   distância.
3. Filtrar a lista por tags de especialidade (ex.: TEA, TDAH, ansiedade, terapia sensorial).
4. Ver o detalhe de um profissional (bio, cidade, especialidades) e contatá-lo diretamente por
   WhatsApp ou telefone, saindo do app — sem nenhum fluxo de agendamento dentro do Sincro.

A equipe Sincro deve poder, a partir de uma conta marcada como admin:

5. Cadastrar, editar e desativar profissionais no diretório, por uma tela dentro do próprio app
   Flutter.

## Fora de escopo

- **Autocadastro de profissionais.** O diretório é 100% curado/mantido pela equipe Sincro — criar
  um fluxo de autocadastro exigiria um segundo tipo de conta com seu próprio auth/verificação,
  provavelmente um pilar multi-fase à parte (mesmo padrão de decisão do Biofeedback). Rejeitado
  explicitamente.
- **Fonte de dados externa (API de terceiros).** Não existe hoje uma fonte confirmada de
  profissionais neuroafirmativos verificados; o diretório é preenchido manualmente pela equipe.
- **Agendamento/solicitação de consulta dentro do app.** O contato é sempre um handoff externo
  (WhatsApp/telefone), mesmo padrão já usado pela Rede de Apoio. Agendamento in-app dependeria do
  sistema de conta de profissional já descartado acima.
- **Geocoding automático de endereço.** Latitude/longitude são digitadas manualmente pelo admin ao
  cadastrar um profissional — sem integração com API de geocoding (sem fonte/custo confirmado,
  diretório pequeno o suficiente para não justificar automação agora).
- **Matching automático com a anamnese.** A busca não cruza tags de especialidade com os dados do
  perfil sensorial/executivo do usuário — o usuário filtra manualmente pelas tags que quiser. Evita
  acoplar este pilar aos dados da anamnese e uma lógica de recomendação para manter.
- **Fallback de endereço/CEP digitado.** A busca depende do GPS do dispositivo; se a permissão for
  negada, o app orienta o usuário a conceder/ajustar a permissão, sem um caminho alternativo de
  digitar localização manualmente.
- **Raio de busca configurável e paginação.** A busca retorna todos os profissionais ativos
  ordenados por distância, sem corte de raio nem paginação — aceitável para um diretório curado e
  pequeno; fácil de adicionar depois se o diretório crescer.
- **Foto de perfil, avaliações, preço, atendimento online.** Fora do conjunto essencial de campos
  desta primeira versão.

## Arquitetura

### Modelo de dados (backend)

Novo model Prisma `Professional` (`@@map("profissionais")`), seguindo a convenção de nomes em
português do schema existente:

- `id`, `nome`, `tags` (`String[]`), `cidade`, `latitude`/`longitude` (`Float`), `telefone`
  (usado tanto para ligação quanto WhatsApp), `bio` (texto curto), `ativo` (`Boolean`, default
  `true` — soft-delete), `createdAt`/`updatedAt`.
- Tags são um array de strings livre no próprio registro, sem tabela/catálogo separado — a equipe
  Sincro digita consistentemente; a tela de busca do usuário deriva as tags disponíveis para
  filtro a partir do que já existe no diretório.

`User` ganha um campo `isAdmin` (`Boolean`, default `false`). Reaproveita a autenticação Firebase
já existente — não é um sistema de conta separado. Ativado manualmente no banco de dados para as
contas da equipe Sincro; não há fluxo de "promover a admin" pelo app.

### Cálculo de distância

Distância calculada via fórmula de Haversine, aplicada na query de busca (SQL raw ou
pós-processamento em JS sobre o resultado). Sem PostGIS nem nenhuma extensão geoespacial —
desnecessário para um diretório pequeno e curado.

### API (backend)

- `GET /professionals/search?lat=&lng=&tags=` — autenticado via Firebase (mesmo guard do resto do
  backend), retorna profissionais `ativo=true` ordenados por distância crescente a partir de
  `lat`/`lng`; `tags` opcional filtra por interseção com as tags do usuário.
- `GET /professionals/tags` — lista as tags distintas presentes no diretório ativo, usada para
  montar os filtros da tela de busca.
- `POST /admin/professionals`, `PATCH /admin/professionals/:id`, `DELETE /admin/professionals/:id`
  (soft-delete: seta `ativo=false`), `GET /admin/professionals` (lista completa, incluindo
  inativos) — todos protegidos por um guard que verifica `user.isAdmin === true` no token Firebase
  já validado; retornam 403 para contas não-admin.

### Mobile: UI

- **Home:** novo card "Encontrar profissional" → tela de busca.
- **Tela de busca:**
  - Ao abrir, solicita permissão de localização (`geolocator`). Concedida, busca automaticamente
    por perto.
  - Negada/indisponível: estado calmo explicando que a localização é necessária para a busca, com
    ação para tentar novamente ou abrir as configurações do app — sem digitar endereço como
    alternativa.
  - Filtros de tag (chips/checkboxes) acima da lista, populados por `GET /professionals/tags`.
  - Lista ordenada por distância: nome, tags, cidade, distância aproximada (ex.: "3.2 km").
  - Lista vazia (sem profissionais cadastrados na região, ou filtro sem resultado): mensagem
    neutra, sem parecer erro.
- **Tela de detalhe:** bio, cidade, tags, botão de contato — abre WhatsApp (`https://wa.me/`) ou
  discador, mesmo padrão de handoff já usado na Rede de Apoio.
- **Tela admin** (`/admin/professionals`): visível na navegação apenas quando o perfil do usuário
  logado tem `isAdmin === true`. Lista completa (incluindo inativos) + formulário de
  criar/editar (nome, tags, cidade, latitude, longitude, telefone, bio) + ação de desativar
  (soft-delete, com confirmação).

### Erros

- Falha de rede na busca ou na tela admin: estado calmo "não foi possível buscar agora" com opção
  de tentar novamente, sem retry automático agressivo — mesmo tom do resto do app.
- Latitude/longitude inválidas no formulário admin (fora do intervalo -90..90 / -180..180):
  validação no formulário antes de enviar, e validação espelhada no backend.

## Segurança e Privacidade

- Todos os endpoints (busca e admin) exigem autenticação Firebase, como o resto do backend.
- Endpoints admin adicionalmente exigem `isAdmin === true`; contas comuns recebem 403 e a tela
  admin nunca aparece na navegação para elas.
- Localização do usuário (lat/lng do GPS) é enviada apenas como parâmetro da busca — não é
  persistida no backend.
- Dados de profissionais (nome, contato, endereço aproximado) são informação pública/curada pela
  Sincro, não dado sensível do usuário.

## Testes

- **Backend:**
  - Cálculo de distância (Haversine): testado isoladamente com coordenadas conhecidas.
  - Endpoint de busca: ordenação por distância e filtro por tags, com dados de teste.
  - Guard admin: acesso permitido para `isAdmin=true`, 403 para `isAdmin=false` e para não
    autenticado.
  - CRUD admin: criar/editar/desativar profissional, e que `DELETE` é soft (registro continua no
    banco com `ativo=false`).
- **Mobile:**
  - Estados da tela de busca (permissão negada, carregando, lista vazia, lista com resultados,
    erro de rede) via testes de widget, com `geolocator` mockado.
  - Formulário admin: validação de latitude/longitude.
  - Visibilidade condicional do card/rota admin conforme `isAdmin`.
- **Verificação manual** (não automatizável em `flutter test`): diálogo de permissão de
  localização nativo em dispositivo real (Android/iOS), abertura do WhatsApp/discador a partir do
  botão de contato.
