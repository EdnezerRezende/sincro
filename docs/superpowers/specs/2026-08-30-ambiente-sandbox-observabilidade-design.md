# Ambiente sandbox de testes + observabilidade

**Status:** Aprovado para planejamento
**Data:** 2026-08-30

## Contexto e objetivo

O Sincro hoje roda inteiramente local, via `docker-compose` (Postgres+pgvector, backend NestJS, mobile-web). Não existe nenhum ambiente acessível fora da máquina de desenvolvimento.

O objetivo é montar um ambiente **sandbox** publicamente acessível para que um grupo fechado de testadores (a ser selecionado pelo usuário) possa validar a aplicação, com:

- Custo zero ou muito baixo (fase de testes, não produção).
- Facilidade de aplicar correções e reimplantar rapidamente.
- Observabilidade mínima viável: rastreamento de erros (backend + mobile).
- Um plano de implementação que qualquer sessão/agente consiga retomar sem contexto prévio, com progresso rastreável e tarefas paralelizáveis onde fizer sentido.

## Decisões (via brainstorming com o usuário)

| Decisão | Escolha | Razão |
|---|---|---|
| Hosting do backend | VPS Oracle Cloud Always Free | Cron jobs internos (`@Cron`) exigem processo Node sempre ativo — incompatível com Vercel serverless. Tiers free de Render/Railway "dormem" após inatividade, quebrando a sincronização periódica. Oracle Cloud Always Free é genuinamente grátis e sempre ativo. |
| Hosting do mobile-web | Mesma VPS (nginx), não Vercel | Usuário preferiu manter um único lugar para administrar, mesmo com a opção de descarregar para Vercel disponível. |
| Banco de dados | Postgres+pgvector na própria VPS (Docker), não Supabase | Mantém o ambiente sandbox como espelho fiel do ambiente de desenvolvimento local; evita mais uma peça externa para uma fase de teste. |
| Domínio | Subdomínio grátis via DuckDNS | Usuário não tem domínio próprio ainda; DuckDNS permite trocar por domínio próprio depois sem grande retrabalho. |
| TLS | Let's Encrypt via Caddy | Renovação automática, configuração mínima. |
| Distribuição Android | Firebase App Distribution | Grátis, projeto Firebase (`sincro-3ac01`) já existe, feito sob medida para testes fechados. |
| Distribuição iOS/desktop | Build Flutter Web na mesma VPS | Evita custo de conta Apple Developer (US$99/ano) nesta fase. |
| Observabilidade | Sentry (backend + Flutter), free tier | Único item de observabilidade solicitado pelo usuário nesta fase (logs centralizados e dashboards de métricas ficaram fora de escopo por ora). |

## Arquitetura

```
Internet
   │
   ▼
[Caddy] :443 (TLS automático via Let's Encrypt + DuckDNS)
   │
   ├── sandbox.SEUDOMINIO.duckdns.org/api/*  → backend (NestJS, :3000, rede interna Docker)
   └── sandbox.SEUDOMINIO.duckdns.org/*      → mobile-web (nginx, :80, rede interna Docker)

Postgres+pgvector → só na rede interna Docker, nunca exposto publicamente

Android → APK assinado, distribuído via Firebase App Distribution
         → aponta para API_BASE_URL=https://sandbox.SEUDOMINIO.duckdns.org/api
```

Firewall da VPS libera apenas as portas 22 (SSH), 80 e 443. Postgres (5432) e o backend (3000) ficam acessíveis somente dentro da rede Docker interna — o Caddy é o único ponto de entrada externo.

## Componentes

### 1. VPS (Oracle Cloud Always Free)
- Instância Ampere A1 (4 OCPU / 24GB RAM) rodando Ubuntu LTS.
- Docker + Docker Compose instalados.
- Firewall (iptables/ufw + Oracle Cloud Security List) restrito a 22/80/443.

### 2. Domínio e TLS
- Subdomínio DuckDNS (ex.: `sincro-sandbox.duckdns.org`) apontando para o IP público da VPS, com atualização automática via cron/script do DuckDNS.
- Caddy como reverse proxy: TLS automático via Let's Encrypt, roteamento por path (`/api/*` → backend, resto → mobile-web).

### 3. Backend + banco
- Reaproveita `backend/Dockerfile` e a estrutura do `docker-compose.yml` existente.
- Novo `docker-compose.sandbox.yml` como overlay: variáveis de ambiente de produção, sem bind mounts de desenvolvimento, `restart: unless-stopped` em todos os serviços.
- Segredos (`backend/.env` de sandbox) vivem só na VPS, nunca versionados.
- Backup diário do Postgres via `pg_dump` (cron do SO), retenção de 7 dias, em volume separado do container.
- Google OAuth: novo redirect URI/domínio autorizado adicionado ao Client Web existente (mesmo client, novo domínio).

### 4. Deploy e fluxo de correções
- Script `deploy.sh` na raiz do projeto (roda via SSH na VPS): `git pull && docker compose -f docker-compose.yml -f docker-compose.sandbox.yml up -d --build`.
- Esse é o mesmo fluxo manual já usado nesta sessão para reconstruir localmente — a mudança é só rodar via SSH na VPS em vez de local.

### 5. Distribuição mobile
- **Android**: build de release assinado (keystore de release, não debug) com `API_BASE_URL` apontando para o domínio sandbox; upload via Firebase CLI (`firebase appdistribution:distribute`); testadores convidados por e-mail via Firebase Console.
- **iOS/desktop**: `flutter build web --release --dart-define=API_BASE_URL=...` servido pelo container nginx já existente na mesma VPS.

### 6. Observabilidade (Sentry)
- Backend: pacote `@sentry/nestjs` capturando exceptions não tratadas, com DSN via variável de ambiente.
- Flutter: pacote `sentry_flutter` capturando crashes/exceptions Dart e nativos (Android), inicializado em `main.dart`.
- Free tier do Sentry cobre o volume esperado de um teste fechado.

## Fora de escopo (nesta fase)

- Logs centralizados/pesquisáveis e dashboards de métricas (usuário optou só por rastreamento de erros por agora — pode ser adicionado depois).
- CI/CD automatizado (deploy continua manual via script/SSH).
- Distribuição iOS nativa via TestFlight (exigiria conta Apple Developer paga).
- Ambiente de produção "de verdade" (este é um ambiente de teste fechado, não dimensionado para escala).

## Critérios de sucesso

- Backend e mobile-web acessíveis via HTTPS no domínio DuckDNS, sem erros de certificado.
- Login Google, conexão Gmail e conexão Pluggy funcionando no ambiente sandbox (mesma validação já feita localmente nesta sessão).
- Um erro proposital no backend (ex.: exception não tratada) aparece no Sentry em poucos minutos.
- Um crash proposital no app Android aparece no Sentry.
- Um testador consegue instalar o app via link do Firebase App Distribution sem precisar de acesso ao código-fonte.
- Aplicar uma correção de código e reimplantar leva um único comando (`./deploy.sh`) rodado via SSH.
