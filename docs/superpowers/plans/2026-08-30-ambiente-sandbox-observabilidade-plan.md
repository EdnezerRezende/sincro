# Ambiente Sandbox de Testes + Observabilidade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Colocar o Sincro (backend NestJS + Postgres/pgvector + mobile) num ambiente público de testes fechado, sem custo mensal fixo, com rastreamento de erros e um fluxo de correção/reimplantação de um único comando.

**Architecture:** Uma VPS gratuita (Oracle Cloud Always Free) roda o mesmo `docker-compose` já usado em desenvolvimento (Postgres+pgvector, backend, mobile-web), atrás de um reverse proxy Caddy que termina TLS automático via Let's Encrypt num subdomínio DuckDNS. Android é distribuído via Firebase App Distribution; testadores sem Android usam a build Flutter Web servida pela mesma VPS. Sentry captura exceptions no backend e crashes no app.

**Tech Stack:** Docker Compose, Caddy (reverse proxy + TLS), DuckDNS (DNS dinâmico grátis), Oracle Cloud Always Free (VPS), Firebase App Distribution, `@sentry/nestjs`, `sentry_flutter`.

**Spec:** [docs/superpowers/specs/2026-08-30-ambiente-sandbox-observabilidade-design.md](../specs/2026-08-30-ambiente-sandbox-observabilidade-design.md)

## Global Constraints

- Custo zero ou muito baixo — nada de tiers pagos além do que já existe (Firebase, Sentry free tier).
- O backend precisa ficar **sempre ativo** (cron jobs internos) — nada de hosting que "dorme" por inatividade.
- Tudo roda numa única VPS (backend, Postgres, mobile-web) — sem Vercel, sem Supabase.
- Postgres+pgvector fica só na rede Docker interna, nunca exposto publicamente.
- Firewall da VPS libera apenas as portas 22 (SSH), 80 e 443.
- Domínio: subdomínio DuckDNS (sem domínio próprio nesta fase).
- Observabilidade desta fase é só rastreamento de erros (Sentry) — sem logs centralizados nem dashboards de métricas.
- Distribuição Android via Firebase App Distribution (projeto Firebase `sincro-3ac01` já existe); iOS/desktop via build Flutter Web.
- Segredos (`.env`) nunca versionados no git — só existem na VPS.

---

## Progress Tracking

> Qualquer sessão/agente que retomar este plano deve primeiro ler esta seção para saber onde o trabalho parou. Marque `[x]` a task e preencha a coluna **Status/Notas** ao concluir (ou ao bloquear) uma task — não deixe isso para o final.

| Task | Título | Pode paralelizar com | Depende de | Status/Notas |
|---|---|---|---|---|
| 1 | `docker-compose.sandbox.yml` overlay | 2, 3, 4, 5, 6 | — | |
| 2 | Caddyfile + script de atualização DuckDNS | 1, 3, 4, 5, 6 | — | |
| 3 | Script `deploy.sh` | 2, 4, 5, 6 | 1 | |
| 4 | Scripts de backup/restore do Postgres | 1, 2, 3, 5, 6 | — | |
| 5 | Sentry no backend | 1, 2, 3, 4, 6 | — | |
| 6 | Sentry no Flutter | 1, 2, 3, 4, 5 | — | |
| 7 | Provisionar VPS + DNS DuckDNS + firewall | — | — (manual, pode começar a qualquer momento) | |
| 8 | Preparar VPS (Docker, clone do repo, `.env` sandbox) | — | 7 | |
| 9 | Primeiro deploy + validar TLS/roteamento | — | 1, 2, 3, 5, 8 | |
| 10 | Atualizar Google OAuth Console pro domínio sandbox | 11 | 7 (precisa do domínio definido) | |
| 11 | Configurar backup cron na VPS | 10 | 4, 8 | |
| 12 | Build Android assinado + Firebase App Distribution | 13 | 9 (precisa da URL do backend) | |
| 13 | Build mobile-web release + deploy | 12 | 9 | |
| 14 | Validação end-to-end (critérios de sucesso da spec) | — | 9, 10, 11, 12, 13 | |

**Paralelização sugerida:**
- **Onda 1** (sem dependências, tudo em paralelo): Tasks 1, 2, 3, 4, 5, 6 são só arquivos no repo — nenhuma depende da VPS existir. Task 7 (provisionamento manual) também pode começar em paralelo com essas.
- **Onda 2** (depende da Onda 1): Task 8 depende só da Task 7. Task 9 depende de 1, 2, 3, 5 e 8.
- **Onda 3**: Tasks 10, 11, 12, 13 podem rodar em paralelo entre si assim que a Task 9 (e a 7, pro domínio) estiverem prontas.
- **Onda 4**: Task 14 fecha o plano, depende de tudo.

---

### Task 1: `docker-compose.sandbox.yml` overlay

**Files:**
- Create: `docker-compose.sandbox.yml`

**Interfaces:**
- Consumes: nada (usa o `docker-compose.yml` existente como base via `-f` overlay).
- Produces: overlay de produção consumido pela Task 3 (`deploy.sh`) e pela Task 9 (primeiro deploy).

- [ ] **Step 1: Criar o overlay de produção**

Cria `docker-compose.sandbox.yml` na raiz do projeto:

```yaml
# Overlay de sandbox/produção: aplicado por cima de docker-compose.yml via
#   docker compose -f docker-compose.yml -f docker-compose.sandbox.yml up -d --build
# Remove bind mounts de dev, garante restart automático e expõe as portas só em loopback
# (127.0.0.1), já que o Caddy (fora deste compose) é quem fala com o mundo externo.
services:
  postgres:
    restart: always
    ports:
      - "127.0.0.1:5433:5432"

  backend:
    restart: always
    ports:
      - "127.0.0.1:3000:3000"
    environment:
      NODE_ENV: production

  mobile-web:
    restart: always
    ports:
      - "127.0.0.1:8080:80"
```

- [ ] **Step 2: Validar sintaxe do compose**

Run: `docker compose -f docker-compose.yml -f docker-compose.sandbox.yml config --quiet`
Expected: nenhum erro impresso (comando silencioso = YAML válido e merge ok).

- [ ] **Step 3: Commit**

```bash
git add docker-compose.sandbox.yml
git commit -m "infra: add sandbox docker-compose overlay"
```

---

### Task 2: Caddyfile + script de atualização DuckDNS

**Files:**
- Create: `infra/Caddyfile`
- Create: `infra/duckdns-update.sh`

**Interfaces:**
- Consumes: nada.
- Produces: `infra/Caddyfile` e `infra/duckdns-update.sh`, copiados para a VPS na Task 8 e usados no primeiro deploy (Task 9). O Caddyfile assume que o backend está acessível em `127.0.0.1:3000` e o mobile-web em `127.0.0.1:8080` (produzido pela Task 1).

- [ ] **Step 1: Criar o Caddyfile**

Cria `infra/Caddyfile`:

```caddyfile
# {$SANDBOX_DOMAIN} é substituído no deploy (ex.: sincro-sandbox.duckdns.org) — ver
# infra/duckdns-update.sh para como o DNS desse domínio é mantido apontando pra VPS.
{$SANDBOX_DOMAIN} {
	handle /api/* {
		uri strip_prefix /api
		reverse_proxy 127.0.0.1:3000
	}

	handle {
		reverse_proxy 127.0.0.1:8080
	}
}
```

- [ ] **Step 2: Criar o script de atualização de DNS do DuckDNS**

Cria `infra/duckdns-update.sh`:

```bash
#!/usr/bin/env bash
# Atualiza o registro A do subdomínio DuckDNS pro IP público atual desta máquina.
# Uso: DUCKDNS_SUBDOMAIN=sincro-sandbox DUCKDNS_TOKEN=xxxx ./duckdns-update.sh
# Pensado pra rodar via cron a cada 5 minutos na VPS (IPs de VPS raramente mudam, mas o Always
# Free da Oracle não garante IP fixo sem reserva explícita — isso cobre esse caso sem custo).
set -euo pipefail

: "${DUCKDNS_SUBDOMAIN:?defina DUCKDNS_SUBDOMAIN (ex.: sincro-sandbox)}"
: "${DUCKDNS_TOKEN:?defina DUCKDNS_TOKEN (encontrado em https://www.duckdns.org apos login)}"

response=$(curl -s "https://www.duckdns.org/update?domains=${DUCKDNS_SUBDOMAIN}&token=${DUCKDNS_TOKEN}&ip=")

if [ "$response" != "OK" ]; then
  echo "Falha ao atualizar DuckDNS: resposta '${response}'" >&2
  exit 1
fi

echo "DuckDNS atualizado com sucesso para ${DUCKDNS_SUBDOMAIN}.duckdns.org"
```

- [ ] **Step 3: Tornar o script executável**

Run: `chmod +x infra/duckdns-update.sh`

- [ ] **Step 4: Commit**

```bash
git add infra/Caddyfile infra/duckdns-update.sh
git commit -m "infra: add Caddy reverse proxy config and DuckDNS updater script"
```

---

### Task 3: Script `deploy.sh`

**Files:**
- Create: `deploy.sh`

**Interfaces:**
- Consumes: `docker-compose.sandbox.yml` (Task 1).
- Produces: comando único de deploy, usado manualmente pelo operador via SSH na VPS (Task 9 em diante) sempre que uma correção precisar ser aplicada.

- [ ] **Step 1: Criar o script**

Cria `deploy.sh` na raiz do projeto:

```bash
#!/usr/bin/env bash
# Reimplanta o ambiente sandbox: puxa a última versão do branch atual e reconstrói os
# containers que mudaram. Rodar via SSH, de dentro do diretório onde o repo foi clonado na VPS
# (ver Task 8 — "Preparar VPS").
set -euo pipefail

cd "$(dirname "$0")"

echo "==> git pull"
git pull

echo "==> docker compose up -d --build"
docker compose -f docker-compose.yml -f docker-compose.sandbox.yml up -d --build

echo "==> containers ativos:"
docker compose -f docker-compose.yml -f docker-compose.sandbox.yml ps

echo "==> deploy concluído"
```

- [ ] **Step 2: Tornar executável**

Run: `chmod +x deploy.sh`

- [ ] **Step 3: Commit**

```bash
git add deploy.sh
git commit -m "infra: add one-command sandbox deploy script"
```

---

### Task 4: Scripts de backup/restore do Postgres

**Files:**
- Create: `infra/backup-postgres.sh`
- Create: `infra/restore-postgres.sh`

**Interfaces:**
- Consumes: nada (assume os nomes de container/serviço já usados em `docker-compose.yml`: serviço `postgres`, banco `sincro_dev`, usuário `sincro`).
- Produces: dumps diários em `infra/backups/` na VPS, consumidos pela Task 11 (cron) e por `restore-postgres.sh` em caso de recuperação manual.

- [ ] **Step 1: Criar o script de backup**

Cria `infra/backup-postgres.sh`:

```bash
#!/usr/bin/env bash
# Dump diário do Postgres com retenção de 7 dias. Pensado pra rodar via cron na VPS
# (ver Task 11). Salva fora do volume do container, para sobreviver a um `docker compose down -v`
# acidental.
set -euo pipefail

cd "$(dirname "$0")/.."

BACKUP_DIR="infra/backups"
mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
FILENAME="${BACKUP_DIR}/sincro_dev-${TIMESTAMP}.sql.gz"

docker compose -f docker-compose.yml -f docker-compose.sandbox.yml exec -T postgres \
  pg_dump -U sincro sincro_dev | gzip > "$FILENAME"

echo "Backup salvo em ${FILENAME}"

# Retenção de 7 dias
find "$BACKUP_DIR" -name "sincro_dev-*.sql.gz" -mtime +7 -delete
```

- [ ] **Step 2: Criar o script de restore**

Cria `infra/restore-postgres.sh`:

```bash
#!/usr/bin/env bash
# Restaura um dump gerado por backup-postgres.sh. USO: ./infra/restore-postgres.sh <arquivo.sql.gz>
# Isso SOBRESCREVE o banco atual — confirme o arquivo antes de rodar.
set -euo pipefail

cd "$(dirname "$0")/.."

FILE="${1:?uso: ./infra/restore-postgres.sh <caminho-do-arquivo.sql.gz>}"

if [ ! -f "$FILE" ]; then
  echo "Arquivo não encontrado: ${FILE}" >&2
  exit 1
fi

echo "Restaurando ${FILE} em sincro_dev — isso sobrescreve os dados atuais."
read -r -p "Confirma? (digite 'sim' para continuar) " confirm
if [ "$confirm" != "sim" ]; then
  echo "Cancelado."
  exit 1
fi

gunzip -c "$FILE" | docker compose -f docker-compose.yml -f docker-compose.sandbox.yml exec -T postgres \
  psql -U sincro sincro_dev

echo "Restore concluído."
```

- [ ] **Step 3: Tornar ambos executáveis**

Run: `chmod +x infra/backup-postgres.sh infra/restore-postgres.sh`

- [ ] **Step 4: Ignorar os dumps no git**

Adiciona ao `.gitignore` (append, sem remover conteúdo existente):

```
infra/backups/
```

- [ ] **Step 5: Commit**

```bash
git add infra/backup-postgres.sh infra/restore-postgres.sh .gitignore
git commit -m "infra: add Postgres backup and restore scripts"
```

---

### Task 5: Sentry no backend

**Files:**
- Modify: `backend/package.json` (nova dependência)
- Modify: `backend/src/main.ts`
- Create: `backend/src/instrument.ts`

**Interfaces:**
- Consumes: variável de ambiente `SENTRY_DSN` (adicionada ao `.env` da VPS na Task 8 — string vazia/ausente = Sentry desabilitado, para não quebrar `flutter run`/`docker compose up` local durante desenvolvimento).
- Produces: exceptions não tratadas do backend aparecendo no projeto Sentry, verificado na Task 14.

- [ ] **Step 1: Instalar a dependência**

Run: `cd backend && npm install @sentry/nestjs @sentry/profiling-node`
Expected: `backend/package.json` e `backend/package-lock.json` atualizados com as duas dependências.

- [ ] **Step 2: Criar o arquivo de inicialização do Sentry**

Cria `backend/src/instrument.ts` (precisa ser importado **antes** de qualquer outro módulo, conforme exigido pelo SDK do Sentry para instrumentar corretamente):

```typescript
import * as Sentry from '@sentry/nestjs';
import { nodeProfilingIntegration } from '@sentry/profiling-node';

// SENTRY_DSN vazio/ausente é um estado válido (dev local, ou a VPS antes do secret ser
// configurado) — Sentry.init com dsn undefined vira um no-op silencioso, então não há guard
// condicional aqui de propósito.
Sentry.init({
  dsn: process.env.SENTRY_DSN,
  environment: process.env.NODE_ENV ?? 'development',
  integrations: [nodeProfilingIntegration()],
  tracesSampleRate: 1.0,
  profilesSampleRate: 1.0,
});
```

- [ ] **Step 3: Importar `instrument.ts` no topo de `main.ts`**

Modifica `backend/src/main.ts` — a primeira linha do arquivo precisa ser o import do instrument (antes até do `dotenv/config`, para o `process.env.SENTRY_DSN` já estar populado no momento do `Sentry.init`, o `dotenv/config` que já existe como primeira linha continua vindo antes):

```typescript
import 'dotenv/config';
import './instrument';
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { rawBody: true });
  // Native mobile clients (Android/iOS) don't send an Origin header, so CORS never applied to
  // them — this was only ever missing for the mobile-web build, which runs in an actual browser
  // and authenticates via a Bearer token (no cookies), so a permissive origin carries no
  // credential-leak risk.
  app.enableCors();
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true }));
  await app.listen(process.env.PORT ?? 3000);
}
bootstrap();
```

- [ ] **Step 4: Verificar que o backend ainda sobe localmente sem `SENTRY_DSN` definido**

Run: `cd backend && npm run build && node dist/src/main.js &` (em seguida `curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/gmail/connection` deve retornar `401` — a rota existe e exige auth, não um erro de boot; depois `kill %1` para encerrar o processo de teste)
Expected: processo sobe sem lançar exception de inicialização; a rota responde `401` (não `000`/conexão recusada).

- [ ] **Step 5: Commit**

```bash
git add backend/package.json backend/package-lock.json backend/src/instrument.ts backend/src/main.ts
git commit -m "feat(backend): add Sentry error tracking"
```

---

### Task 6: Sentry no Flutter

**Files:**
- Modify: `mobile/pubspec.yaml`
- Modify: `mobile/lib/main.dart`

**Interfaces:**
- Consumes: valor `SENTRY_DSN` passado via `--dart-define=SENTRY_DSN=...` no build de release (Task 12/13) — ausente/vazio em `flutter run` local do dia a dia, mesmo raciocínio da Task 5.
- Produces: crashes/exceptions do app Android aparecendo no projeto Sentry, verificado na Task 14.

- [ ] **Step 1: Adicionar a dependência**

Modifica `mobile/pubspec.yaml`, na seção `dependencies` (junto das demais, ordem alfabética não é seguida pelo arquivo hoje — adiciona ao final do bloco existente):

```yaml
  geolocator: ^14.0.2
  sentry_flutter: ^8.14.0
```

Run: `cd mobile && flutter pub get`
Expected: `mobile/pubspec.lock` atualizado com `sentry_flutter` e suas dependências transitivas.

- [ ] **Step 2: Envolver `main()` com `SentryFlutter.init`**

Modifica `mobile/lib/main.dart` — adiciona o import e envolve o corpo de `main()` na chamada de inicialização do Sentry. A const `String.fromEnvironment('SENTRY_DSN')` vazia é o mesmo padrão já usado neste arquivo para `_googleWebClientId` em `email_triage_providers.dart` — string vazia é um DSN inválido para o SDK, então o guard `if` evita chamar `SentryFlutter.init` nesse caso em vez de deixá-lo falhar silenciosamente:

```dart
import 'package:sentry_flutter/sentry_flutter.dart';
```

(adiciona esse import junto aos demais `package:` no topo do arquivo, antes de `firebase_options.dart`)

Substitui a assinatura e o corpo de `main()`:

```dart
const _sentryDsn = String.fromEnvironment('SENTRY_DSN');

Future<void> main() async {
  if (_sentryDsn.isEmpty) {
    await _bootstrap();
    return;
  }
  await SentryFlutter.init(
    (options) => options.dsn = _sentryDsn,
    appRunner: _bootstrap,
  );
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // `workmanager` só tem implementação em Android e iOS; no desktop (Linux/Windows) a chamada
  // lança uma MissingPluginException logo na inicialização do app.
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await Workmanager().initialize(biofeedbackCallbackDispatcher);
  }

  // Os alertas do Biofeedback são um recurso só de Android e iOS, e `initialize()` do
  // flutter_local_notifications lança ArgumentError no desktop (Linux/Windows/macOS) quando as
  // settings da plataforma correspondente vêm nulas — como aqui, que só passa android:/iOS:.
  // Mesmo guard usado pelo workmanager logo acima; inventar settings de desktop para um recurso
  // que só existe no celular só criaria caminho morto.
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await flutterLocalNotificationsPlugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: _handleBiofeedbackAlertTap,
    );
    if (Platform.isAndroid) {
      // POST_NOTIFICATIONS (Android 13+) precisa ser pedida em runtime; em versões mais antigas
      // isto é um no-op.
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }

    // Cold-start via notificação local do Biofeedback: `onDidReceiveNotificationResponse` (acima)
    // nunca dispara para esse caso — só `getNotificationAppLaunchDetails()` reporta. O navigator só
    // está anexado após o primeiro frame, daí o addPostFrameCallback (mesmo padrão do
    // getInitialMessage() do FCM logo abaixo).
    final launchDetails = await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      final response = launchDetails!.notificationResponse;
      if (response != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _handleBiofeedbackAlertTap(response));
      }
    }
  }

  // App backgrounded, not terminated: the Flutter engine is already running, so the navigator
  // is ready by the time this fires.
  FirebaseMessaging.onMessageOpenedApp.listen(_handleEmailTriageNotificationTap);

  // App fully terminated (the realistic case after a background sync push): tapping the
  // notification cold-starts the app. onMessageOpenedApp never fires for this case — only
  // getInitialMessage() reports it, and the navigator isn't attached yet until after the first
  // frame, so the navigation is deferred with addPostFrameCallback (same pattern used elsewhere
  // in this codebase, e.g. onboarding_router.dart's post-build redirect).
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleEmailTriageNotificationTap(initialMessage));
  }

  runApp(const ProviderScope(child: SincroApp()));
}
```

- [ ] **Step 3: Verificar que o app ainda compila e roda sem `SENTRY_DSN`**

Run: `cd mobile && flutter analyze lib/main.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add mobile/pubspec.yaml mobile/pubspec.lock mobile/lib/main.dart
git commit -m "feat(mobile): add Sentry crash reporting"
```

---

### Task 7: Provisionar VPS + DNS DuckDNS + firewall

**Files:** nenhum (ações manuais fora do repositório — o usuário executa; um agente com acesso de terminal e navegador pode conduzir, mas a criação de conta exige dados pessoais/cartão que só o usuário tem).

**Interfaces:**
- Consumes: nada.
- Produces: **IP público da VPS** e **subdomínio DuckDNS** (ex.: `sincro-sandbox.duckdns.org` → IP da VPS) e **token DuckDNS** — os três valores são consumidos pelas Tasks 8, 9 e 10.

- [ ] **Step 1: Criar a instância na Oracle Cloud**

1. Acesse https://cloud.oracle.com/ e crie uma conta (Always Free tier).
2. No console, vá em **Compute → Instances → Create Instance**.
3. Escolha a imagem **Canonical Ubuntu 24.04** (ou a LTS mais recente disponível).
4. Em **Shape**, selecione **VM.Standard.A1.Flex** (Ampere, elegível ao Always Free) com 2 OCPUs / 12 GB RAM (dentro da cota gratuita de 4 OCPU/24GB total, deixando margem para outra instância no futuro se quiser).
5. Em **Add SSH keys**, gere um novo par de chaves (ou cole sua chave pública existente) e **guarde a chave privada** — é o único jeito de acessar a VPS depois.
6. Confirme e crie. Anote o **IP público** exibido após o provisionamento (alguns minutos).

Expected: uma instância `RUNNING` com IP público anotado.

- [ ] **Step 2: Testar acesso SSH**

Run (localmente, substituindo o caminho da chave e o IP): `ssh -i /caminho/para/chave-privada ubuntu@SEU_IP_PUBLICO`
Expected: login bem-sucedido no shell da VPS.

- [ ] **Step 3: Criar o subdomínio DuckDNS**

1. Acesse https://www.duckdns.org/ e faça login (GitHub/Google/Reddit).
2. Em **domains**, digite um subdomínio livre (ex.: `sincro-sandbox`) e clique **add domain**.
3. Anote o **token** exibido no topo da página (é o `DUCKDNS_TOKEN` usado em `infra/duckdns-update.sh`, Task 2).
4. No campo do domínio criado, cole o IP público da instância (Step 1) e clique **update ip**.

Expected: `nslookup sincro-sandbox.duckdns.org` (ou o subdomínio escolhido) resolve para o IP público da VPS.

- [ ] **Step 4: Abrir as portas 80/443 na Security List da Oracle Cloud**

Por padrão a Oracle Cloud bloqueia tudo além da porta 22 numa camada de firewall própria (Security List), separada do firewall do SO:

1. No console Oracle Cloud, vá em **Networking → Virtual Cloud Networks** → selecione a VCN da instância → **Security Lists** → a lista padrão.
2. **Add Ingress Rules** duas vezes:
   - Source CIDR `0.0.0.0/0`, IP Protocol `TCP`, Destination Port `80`.
   - Source CIDR `0.0.0.0/0`, IP Protocol `TCP`, Destination Port `443`.

Expected: as duas regras aparecem na lista, junto da regra pré-existente da porta 22.

- [ ] **Step 5: Configurar o firewall do SO (ufw) na VPS**

Via SSH (conexão do Step 2):

```bash
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable
sudo ufw status
```

Expected: `ufw status` lista as três portas como `ALLOW`, e a conexão SSH atual não cai (confirma que a 22 continua liberada antes de fechar o terminal).

---

### Task 8: Preparar VPS (Docker, clone do repo, `.env` sandbox)

**Files:** nenhum no repo local — ações executadas via SSH na VPS.

**Interfaces:**
- Consumes: IP/acesso SSH da VPS (Task 7).
- Produces: repositório clonado em `~/sincro` na VPS, Docker funcional, `backend/.env` de sandbox populado — consumidos pela Task 9.

- [ ] **Step 1: Instalar Docker e Docker Compose**

Via SSH, na VPS:

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
```

Encerre a sessão SSH e reconecte (para o grupo `docker` ter efeito), depois confirme:

```bash
docker --version
docker compose version
```

Expected: ambos os comandos imprimem uma versão, sem erro de permissão.

- [ ] **Step 2: Clonar o repositório**

```bash
git clone https://github.com/EdnezerRezende/sincro.git ~/sincro
cd ~/sincro
```

Expected: diretório `~/sincro` populado com o conteúdo do repo (mesmo branch `master` usado em desenvolvimento).

- [ ] **Step 3: Criar `backend/.env` de sandbox**

Não existe um `.env` de exemplo versionado (o arquivo é gitignored por design). Cria `~/sincro/backend/.env` na VPS com o mesmo formato usado localmente (ver `backend/src/main.ts`/serviços para as chaves lidas via `process.env`), preenchendo com **credenciais de sandbox** (não as mesmas do dev local, para poder revogar/trocar sem afetar sua máquina):

```bash
cat > ~/sincro/backend/.env <<'EOF'
DATABASE_URL="postgresql://sincro:sincro_dev_password@localhost:5432/sincro_dev"
FIREBASE_PROJECT_ID="sincro-3ac01"
FIREBASE_CLIENT_EMAIL="firebase-adminsdk-fbsvc@sincro-3ac01.iam.gserviceaccount.com"
FIREBASE_PRIVATE_KEY="COLE_AQUI_A_PRIVATE_KEY_DO_SERVICE_ACCOUNT"
TOKEN_ENCRYPTION_KEY="GERE_UMA_NOVA_COM_openssl_rand_base64_32"
GOOGLE_CLIENT_ID="393611506422-g0ufsk76bb8kk4krc7g2tvg9uipibr6c.apps.googleusercontent.com"
GOOGLE_CLIENT_SECRET="COLE_AQUI_O_CLIENT_SECRET_ATUAL"
ANTHROPIC_API_KEY="COLE_AQUI"
OPENAI_API_KEY="COLE_AQUI"
PLUGGY_CLIENT_ID="COLE_AQUI"
PLUGGY_CLIENT_SECRET="COLE_AQUI"
PLUGGY_WEBHOOK_SECRET="COLE_AQUI"
SENTRY_DSN="COLE_AQUI_APOS_CRIAR_O_PROJETO_NO_SENTRY_NA_TASK_14"
EOF
```

`TOKEN_ENCRYPTION_KEY` **precisa** ser gerada nova (não reaproveitar a de dev local) — gere com `openssl rand -base64 32` e cole o resultado. As demais chaves (Firebase, Google, Anthropic, OpenAI, Pluggy) podem ser as mesmas já usadas localmente, encontradas em `backend/.env` na sua máquina de desenvolvimento.

Expected: `cat ~/sincro/backend/.env` na VPS mostra todas as chaves preenchidas (nenhuma com o texto literal `COLE_AQUI...`).

- [ ] **Step 4: Restringir permissões do arquivo de segredos**

```bash
chmod 600 ~/sincro/backend/.env
```

Expected: `ls -l ~/sincro/backend/.env` mostra `-rw-------`.

---

### Task 9: Primeiro deploy + validar TLS/roteamento

**Files:** nenhum no repo local — execução via SSH na VPS.

**Interfaces:**
- Consumes: `docker-compose.sandbox.yml` (Task 1), `infra/Caddyfile` + `infra/duckdns-update.sh` (Task 2), `deploy.sh` (Task 3), mudanças de Sentry (Task 5), VPS preparada com `.env` (Task 8), subdomínio DuckDNS (Task 7).
- Produces: ambiente sandbox acessível publicamente em `https://SEU_SUBDOMINIO.duckdns.org`, consumido pelas Tasks 10 a 14.

- [ ] **Step 1: Instalar o Caddy na VPS**

```bash
sudo apt update
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install -y caddy
```

Expected: `caddy version` imprime uma versão instalada.

- [ ] **Step 2: Publicar o Caddyfile do repo**

Caddy expande `{$VAR}` a partir do seu próprio ambiente de processo no momento de carregar o config — não precisa de substituição de texto. Copia o Caddyfile como está e define a variável via systemd:

```bash
sudo cp ~/sincro/infra/Caddyfile /etc/caddy/Caddyfile
sudo systemctl edit caddy
```

No editor que abrir, adiciona (substituindo pelo subdomínio real da Task 7):

```ini
[Service]
Environment=SANDBOX_DOMAIN=SEU_SUBDOMINIO.duckdns.org
```

Salva e sai, depois:

```bash
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl restart caddy
```

Expected: `caddy validate` reporta "Valid configuration"; `sudo systemctl status caddy` mostra `active (running)`, sem erros no `journalctl -u caddy -n 50`.

- [ ] **Step 3: Subir os containers do sandbox**

```bash
cd ~/sincro
./deploy.sh
```

Expected: saída do script termina em "deploy concluído"; `docker compose -f docker-compose.yml -f docker-compose.sandbox.yml ps` mostra os três serviços (`postgres`, `backend`, `mobile-web`) com status `Up`/`healthy`.

- [ ] **Step 4: Validar HTTPS e roteamento de fora da VPS**

Do seu computador local (não da VPS):

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://SEU_SUBDOMINIO.duckdns.org/api/gmail/connection
curl -s -o /dev/null -w "%{http_code}\n" https://SEU_SUBDOMINIO.duckdns.org/
```

Expected: primeiro comando retorna `401` (rota do backend existe, exige auth — confirma que `/api/*` chega no NestJS); segundo retorna `200` (confirma que a raiz serve o mobile-web); nenhum dos dois apresenta erro de certificado TLS.

- [ ] **Step 5: Configurar o cron do DuckDNS updater**

```bash
crontab -e
```

Adiciona a linha (substituindo subdomínio e token pelos da Task 7):

```
*/5 * * * * DUCKDNS_SUBDOMAIN=SEU_SUBDOMINIO DUCKDNS_TOKEN=SEU_TOKEN /home/ubuntu/sincro/infra/duckdns-update.sh >> /home/ubuntu/duckdns.log 2>&1
```

Expected: `crontab -l` lista a linha; após 5 minutos, `cat ~/duckdns.log` mostra "DuckDNS atualizado com sucesso".

---

### Task 10: Atualizar Google OAuth Console pro domínio sandbox

**Files:** nenhum (configuração no Google Cloud Console — mesmo Client Web já usado, `393611506422-g0ufsk76bb8kk4krc7g2tvg9uipibr6c.apps.googleusercontent.com`).

**Interfaces:**
- Consumes: subdomínio DuckDNS (Task 7).
- Produces: login Google e conexão Gmail funcionando no domínio sandbox, verificado na Task 14.

- [ ] **Step 1: Adicionar o domínio autorizado**

1. Acesse https://console.cloud.google.com/apis/credentials?project=sincro-3ac01
2. Abra o client **Web client (auto created by Google Service)** (`g0ufsk76bb8kk4krc7g2tvg9uipibr6c`).
3. Em **Origens JavaScript autorizadas**, clique **+ Adicionar URI** e adicione `https://SEU_SUBDOMINIO.duckdns.org`.
4. Em **URIs de redirecionamento autorizados**, clique **+ Adicionar URI** e adicione `https://SEU_SUBDOMINIO.duckdns.org`.
5. Clique **Salvar**.

Expected: as duas novas URIs aparecem salvas na tela do client (pode levar alguns minutos para propagar, conforme aviso do próprio Console).

- [ ] **Step 2: Adicionar o domínio ao Branding (Domínios autorizados)**

1. Em https://console.cloud.google.com/auth/branding?project=sincro-3ac01, na seção **Domínios autorizados**, clique **+ Adicionar domínio**.
2. Adicione `duckdns.org`.
3. Salve.

Expected: `duckdns.org` listado nos domínios autorizados.

---

### Task 11: Configurar backup cron na VPS

**Files:** nenhum no repo local — execução via SSH na VPS.

**Interfaces:**
- Consumes: `infra/backup-postgres.sh` (Task 4), VPS com repo clonado (Task 8).
- Produces: dumps diários em `~/sincro/infra/backups/`, verificado na Task 14.

- [ ] **Step 1: Testar o backup manualmente uma vez**

```bash
cd ~/sincro
./infra/backup-postgres.sh
ls -lh infra/backups/
```

Expected: um arquivo `sincro_dev-YYYYMMDD-HHMMSS.sql.gz` com tamanho maior que zero.

- [ ] **Step 2: Agendar via cron**

```bash
crontab -e
```

Adiciona a linha (backup diário às 3h da manhã):

```
0 3 * * * /home/ubuntu/sincro/infra/backup-postgres.sh >> /home/ubuntu/backup.log 2>&1
```

Expected: `crontab -l` lista a linha junto da linha do DuckDNS updater (Task 9, Step 5).

---

### Task 12: Build Android assinado + Firebase App Distribution

**Files:**
- Create: `mobile/android/key.properties` (não versionado — adicionar ao `.gitignore`)
- Modify: `mobile/android/app/build.gradle.kts`
- Modify: `mobile/.gitignore` (ou `mobile/android/.gitignore`, o que já existir)

**Interfaces:**
- Consumes: URL do backend sandbox (Task 9), `SENTRY_DSN` do projeto Flutter no Sentry (criado durante a Task 14, ou antes se o operador já tiver o DSN).
- Produces: APK de release distribuído aos testadores via Firebase App Distribution, verificado na Task 14.

- [ ] **Step 1: Gerar o keystore de release**

```bash
cd mobile/android/app
keytool -genkey -v -keystore release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias sincro-sandbox
```

Responda às perguntas do `keytool` (nome, organização, etc. — podem ser dados fictícios para um ambiente de teste) e defina uma senha para o keystore e para a chave. **Guarde essas senhas** — sem elas não é possível gerar novos builds compatíveis com o mesmo app instalado pelos testadores.

Expected: arquivo `mobile/android/app/release-key.jks` criado.

- [ ] **Step 2: Criar `key.properties`**

Cria `mobile/android/key.properties` (senhas do Step 1):

```properties
storePassword=SENHA_DO_KEYSTORE
keyPassword=SENHA_DA_CHAVE
keyAlias=sincro-sandbox
storeFile=release-key.jks
```

- [ ] **Step 3: Ignorar os segredos de assinatura no git**

Adiciona ao `.gitignore` da raiz do projeto (append):

```
mobile/android/key.properties
mobile/android/app/release-key.jks
```

- [ ] **Step 4: Configurar o signing config de release**

Modifica `mobile/android/app/build.gradle.kts` — adiciona a leitura do `key.properties` no topo do arquivo (antes do bloco `plugins`) e substitui o `signingConfig` de `release`:

```kotlin
import java.util.Properties
import java.io.FileInputStream
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}
```

E dentro do bloco `android { ... }`, adiciona `signingConfigs` e ajusta `buildTypes`:

```kotlin
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Só usa o signing de release de verdade quando key.properties existe (VPS/CI de
            // sandbox); em dev local sem esse arquivo, cai de volta pro debug key, preservando
            // `flutter run --release` como já funcionava antes desta task.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
```

- [ ] **Step 5: Build do APK de release**

```bash
cd mobile
flutter build apk --release \
  --dart-define=API_BASE_URL=https://SEU_SUBDOMINIO.duckdns.org/api \
  --dart-define=GOOGLE_WEB_CLIENT_ID=393611506422-g0ufsk76bb8kk4krc7g2tvg9uipibr6c.apps.googleusercontent.com \
  --dart-define=SENTRY_DSN=SEU_DSN_DO_SENTRY_FLUTTER
```

Expected: `build/app/outputs/flutter-apk/app-release.apk` gerado sem erros.

- [ ] **Step 6: Instalar a CLI do Firebase e autenticar**

```bash
npm install -g firebase-tools
firebase login
```

Expected: login concluído no navegador; `firebase projects:list` inclui `sincro-3ac01`.

- [ ] **Step 7: Registrar o app no Firebase App Distribution e distribuir**

```bash
firebase appdistribution:distribute \
  build/app/outputs/flutter-apk/app-release.apk \
  --app FIREBASE_APP_ID_ANDROID \
  --groups "testadores-sandbox"
```

(`FIREBASE_APP_ID_ANDROID` está em `mobile/android/app/google-services.json`, campo `mobilesdk_app_id` dentro de `client[0].client_info` — já visto nesta sessão como `1:393611506422:android:f864f79df7084de28972d7`.)

Se o grupo `testadores-sandbox` ainda não existir, crie-o antes em https://console.firebase.google.com/project/sincro-3ac01/appdistribution → **Testadores e grupos** → **Adicionar grupo**, e convide os e-mails dos testadores selecionados.

Expected: saída do comando confirma o upload e mostra o link de convite; os testadores recebem e-mail do Firebase App Distribution.

- [ ] **Step 8: Commit das mudanças de build (sem os segredos)**

```bash
git add mobile/android/app/build.gradle.kts .gitignore
git commit -m "feat(mobile): configure release signing for sandbox distribution"
```

---

### Task 13: Build mobile-web release + deploy

**Files:** nenhum novo — reusa `mobile/Dockerfile.web` existente.

**Interfaces:**
- Consumes: URL do backend sandbox (Task 9).
- Produces: build Flutter Web servida em `https://SEU_SUBDOMINIO.duckdns.org/`, verificado na Task 14.

- [ ] **Step 1: Confirmar o `API_BASE_URL` usado pelo container `mobile-web`**

O `docker-compose.yml` já builda `mobile-web` a partir de `mobile/Dockerfile.web`, que aceita `ARG API_BASE_URL` (visto nos logs de build desta sessão: `Step 5/11 : ARG API_BASE_URL=http://localhost:3000`). Esse valor precisa apontar para o próprio domínio sandbox — não para `localhost`, já que quem acessa é o navegador do testador, não a VPS.

- [ ] **Step 2: Adicionar o build arg no compose de sandbox**

Modifica `docker-compose.sandbox.yml` (criado na Task 1), adicionando `build.args` ao serviço `mobile-web`:

```yaml
  mobile-web:
    restart: always
    build:
      args:
        API_BASE_URL: https://SEU_SUBDOMINIO.duckdns.org/api
    ports:
      - "127.0.0.1:8080:80"
```

- [ ] **Step 3: Redeploy**

Na VPS:

```bash
cd ~/sincro
./deploy.sh
```

Expected: o serviço `mobile-web` é reconstruído (log do Docker mostra `Step 5/11 : ARG API_BASE_URL=https://SEU_SUBDOMINIO.duckdns.org/api` refletindo o novo valor, não mais `localhost`).

- [ ] **Step 4: Validar no navegador**

Abra `https://SEU_SUBDOMINIO.duckdns.org/` num navegador comum (fora da VPS) e tente fazer login.
Expected: a tela de login carrega e uma tentativa de login dispara uma requisição de rede visível nas DevTools para `https://SEU_SUBDOMINIO.duckdns.org/api/...` (não para `localhost`).

- [ ] **Step 5: Commit**

```bash
git add docker-compose.sandbox.yml
git commit -m "infra: point mobile-web sandbox build at the sandbox domain"
```

---

### Task 14: Validação end-to-end (critérios de sucesso da spec)

**Files:** nenhum — apenas verificação manual, seguindo os critérios de sucesso definidos na spec.

**Interfaces:**
- Consumes: tudo (Tasks 1–13).
- Produces: confirmação de que o ambiente sandbox está pronto para convidar testadores.

- [ ] **Step 1: Criar os projetos no Sentry (se ainda não existirem)**

1. Acesse https://sentry.io e crie (ou reaproveite) uma organização gratuita.
2. Crie um projeto **Node.js/NestJS** — copie o DSN gerado.
3. Crie um segundo projeto **Flutter** — copie o DSN gerado.
4. Atualize `SENTRY_DSN` em `backend/.env` na VPS (Task 8) com o primeiro DSN e rode `./deploy.sh` novamente.
5. Refaça o build Android (Task 12, Step 5) com o segundo DSN em `--dart-define=SENTRY_DSN=...`, e redistribua via Firebase App Distribution (Task 12, Step 7).

Expected: dois projetos Sentry criados, cada um com seu DSN aplicado.

- [ ] **Step 2: Validar HTTPS e certificado**

```bash
curl -vI https://SEU_SUBDOMINIO.duckdns.org/ 2>&1 | grep -i "SSL certificate verify ok"
```

Expected: linha "SSL certificate verify ok" presente.

- [ ] **Step 3: Validar login Google + Gmail no domínio sandbox**

No app Android instalado via Firebase App Distribution (Task 12) ou na versão web (Task 13): faça login com Google e conecte o Gmail, seguindo o mesmo fluxo já validado localmente nesta sessão.
Expected: login e conexão do Gmail completam sem `ApiException: 10` nem erro 500 (mesmos sintomas já resolvidos localmente — confirma que a config do domínio sandbox no Google Console, Task 10, está correta).

- [ ] **Step 4: Validar conexão Pluggy no domínio sandbox**

No app: tente conectar uma conta via Pluggy Connect (fluxo Sandbox, credenciais `user-ok`/`password-ok`, como testado nesta sessão).
Expected: conexão completa e a conta aparece na lista de conexões financeiras.

- [ ] **Step 5: Validar captura de erro no backend**

Force uma exception temporária (ex.: acesse uma rota inexistente que dispare erro 500, ou peça pro backend, via SSH, rodar `docker compose exec backend node -e "throw new Error('teste sandbox sentry')"` — isso não afeta o processo principal do container, é uma execução avulsa).
Expected: o erro aparece no projeto Sentry do backend em até alguns minutos.

- [ ] **Step 6: Validar captura de crash no Flutter**

No app instalado, adicione temporariamente um botão de teste (ou use o DevTools/adb) que force uma exception não tratada — ou simplesmente confirme via `Sentry.captureException` manual documentado no pacote `sentry_flutter`, chamando-o uma vez de qualquer tela via um breakpoint/log temporário.
Expected: o evento aparece no projeto Sentry do Flutter em até alguns minutos.

- [ ] **Step 7: Validar o fluxo de correção rápida**

Faça uma mudança trivial no backend (ex.: um log adicional), commit, push, e rode `./deploy.sh` na VPS.
Expected: um único comando reimplanta a mudança, sem passos manuais extras.

- [ ] **Step 8: Atualizar a tabela de Progress Tracking**

Marca todas as tasks deste plano como `[x]` e preenche a coluna Status/Notas com a data de conclusão e qualquer observação relevante (ex.: subdomínio final escolhido, grupo de testadores criado).
