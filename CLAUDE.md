# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## 🧠 Consulte o Segundo-cérebro

**Sempre que iniciar uma nova sessão ou enfrentar questões sobre contexto, arquitetura ou decisões do projeto, procure no Segundo-cérebro primeiro:**

```
/Users/ed/Library/CloudStorage/OneDrive-Pessoal/Documentos/obsidian/segundo-cerebro/Segundo-cerebro/
```

### Pastas principais:
- **`02_work/projetos/sincro/`** — Status atual, roadmap, backlog e especificações em andamento
- **`04_knowledge_wiki/`** — Conhecimento consolidado (arquitetura, padrões, decisões maduras)
- **`07_mocs/`** — Mapas de conteúdo para navegar temas amplos (`moc_*.md`)
- **`08_daily/`** — Notas cronológicas do dia (contexto recente)

### Como buscar:
1. Use `Grep` por palavra-chave ou tag (`@tag-name`)
2. Leia os `.md` candidatos
3. Siga links `[[wikilink]]` dentro dos arquivos para explorar contexto relacionado

**Exemplo**: Questão sobre integração bancária? Grep por "financas" ou "banco" em `02_work/projetos/sincro/`, depois navegue pelos links.

---

## Quick Reference

### Backend (NestJS)
```bash
cd backend
npm install

# Development
npm run start:dev

# Build & Production
npm run build
npm start:prod

# Linting & Formatting
npm run lint

# Tests
npm run test              # Run all unit tests
npm run test:watch       # Watch mode
npm run test:e2e         # E2E tests
npm run test:cov         # Coverage report
npm run test:debug       # Debug a test
```

### Mobile (Flutter)
```bash
cd mobile

# Required: Gmail OAuth Web Client ID (from backend/.env → GOOGLE_CLIENT_ID)
flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=<your-client-id>

# Web
flutter run -d chrome
flutter build web

# Android (requires signing config in android/app/build.gradle.kts)
flutter build apk --release
flutter build appbundle --release

# iOS (requires HealthKit capability in Xcode, see below)
flutter build ios --release

# Tests
flutter test
```

---

## Architecture Overview

**SINCRO** is a mental health & executive wellness application with three integrated pillars:

### Data & Auth Foundation
- **Database**: PostgreSQL 16 (Prisma ORM, managed migrations)
- **Auth**: Google OAuth2 (Gmail/Calendar), Firebase Auth, JWT + secure token storage via Jasypt
- **Observability**: Sentry (both backend & mobile)

### Backend (NestJS) — Modular Structure
Organized by feature, each with `{module|controller|service|dto|entity}` pattern:

| Module | Purpose |
|--------|---------|
| **auth** | Google OAuth2 flow, JWT issuance, credential encryption |
| **gmail** | Gmail API integration, email sync trigger orchestration |
| **email-sync** | Background job to sync inbox; feeds email-classification & email-reply |
| **email-classification** | ML-based triage (PRECISA_ATENCAO, FINANCEIRO, SOCIAL) via Claude API |
| **email-reply** | AI draft responses to classified emails (Claude) |
| **calendar** | Google Calendar sync, event categorization, auto-scheduling confirmed finance events |
| **financas** | Finance management: account linking, transaction parsing, bank reconnect logic |
| **professionals** | Admin directory of mental health / crisis professionals |
| **grounding-cards** | Library of grounding techniques with tailored suggestions |
| **emergency** | Crisis triggers, trusted contacts, escalation workflow |
| **sensory-profile** & **trusted-contacts** | User profile + support network setup |

**Key Pattern**: Controllers → Services → Prisma/External APIs. Use DTOs for validation (class-validator).

### Mobile (Flutter) — Feature-First Architecture
```
lib/
  core/          # Singleton services, theme, routing, const
  features/      # Each feature folder: providers, screens, widgets, models
    home/        # Landing screen with 4 pillars (Agenda, Financas, Biofeedback, Mental Health)
    email_triage/inbox_screen.dart  # Gmail triage (PRECISA_ATENCAO emails)
    financas/    # Finance dashboard & account linking
    biofeedback/ # HealthKit/Health Connect heart rate + HRV, background sync
    calendar/    # Google Calendar read-only with event categories
    grounding_cards/
    calming_games/ # Voo Sereno (flight), Estrada Tranquila (car)
    professionals/ # Crisis professional search
    ...
  main.dart      # Firebase + Riverpod bootstrap
```

**State Management**: Riverpod (providers for services, cached API calls, biofeedback background sync).  
**Networking**: Dio with JWT interceptor (reads token from SharedPreferences).  
**Biofeedback**: Health package (iOS HealthKit, Android Health Connect) + WorkManager for background sync on iOS/Android.

### Infrastructure — OCI Sandbox
- **VPS**: Oracle Cloud Always Free (Ampere A1 / x86) in Montreal region
- **Containers**: `docker-compose.sandbox.yml` runs API (NestJS), Postgres, and Flutter Web build
- **Reverse Proxy**: Caddy with TLS (Let's Encrypt) + DuckDNS for dynamic DNS
- **Firewall**: Only ports 22 (SSH), 80 (HTTP), 443 (HTTPS) exposed; Postgres lives in Docker-internal network
- **Backup**: `infra/backup-postgres.sh` & `infra/restore-postgres.sh` for DB dumps

---

## Important Platform-Specific Setup

### Mobile: iOS HealthKit
Edit `ios/Runner.xcworkspace` in Xcode → Runner target → Signing & Capabilities → **+ Capability → HealthKit**.  
Keep `biofeedbackTaskName` in `lib/features/biofeedback/biofeedback_background_task.dart` in sync with `BGTaskSchedulerPermittedIdentifiers` in `Info.plist`.

### Mobile: Android Health Connect
- `minSdk = 26` (enforced by `health` package)
- `MainActivity` must be `FlutterFragmentActivity` (Health Connect needs `registerForActivityResult`)
- `AndroidManifest.xml` carries `<queries>` block + `ViewPermissionUsageActivity` alias
- Workmanager dependency overrides in `pubspec.yaml` are pinned—verify when bumping Flutter SDK to >=3.38.0

### Backend: Environment Variables
Create `backend/.env` from `backend/.env.example`. **Critical vars**:
- `DATABASE_URL` — Postgres connection string
- `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` — OAuth (create at cloud.google.com/console)
- `JWT_SECRET` — For token signing
- `ANTHROPIC_API_KEY` — For Claude API (email replies)
- `FIREBASE_*` — Project credentials (download JSON from Firebase console)

### Mobile: Gmail OAuth
Pass `--dart-define=GOOGLE_WEB_CLIENT_ID=<web-client-id>` at run/build time. Without it, Android's native Google Sign-In returns `null` for `serverAuthCode`, connection fails silently with generic error.

---

## Testing & Verification

**Backend**: Jest with ts-jest. Test files colocate as `*.spec.ts` in `src/`. Coverage collected to `coverage/`.

**Mobile**: Flutter test (unit & widget tests). Screenshot harness in `.gauntlet/scripts/` for visual regression.

**E2E (Backend)**: Jest e2e config in `test/jest-e2e.json`. Hit real Postgres and external APIs.

---

## Key Dependencies & Versions

| Pillar | Key Stack |
|--------|-----------|
| **Backend** | NestJS 11, TypeScript 5.7, Prisma 7.9, PostgreSQL 16, Firebase Admin 14, Jest 30 |
| **Mobile** | Flutter 3.32.8, Dart 3.8, Riverpod 3.3, Firebase Auth 6.5, Health 13.3, Workmanager 0.9 |
| **Infrastructure** | Docker Compose, Caddy, DuckDNS, PostgreSQL 16 + pgvector, Ubuntu/Ampere |

---

## Conventions & Patterns

- **Naming**: SCREAMING_SNAKE_CASE for constants, camelCase for functions/vars, PascalCase for classes/types/modules
- **Error Handling**: NestJS `HttpException` with `BadRequestException`, `UnauthorizedException`, etc. Mobile: try/catch with Sentry reporting
- **Logging**: Backend uses Sentry + structured logs. Mobile uses Sentry + Flutter's `debugPrint` (no production logs)
- **Code Style**: Prettier (backend), dartfmt (mobile); ESLint + dart analyzer enforce on commit
- **Async**: Async/await in both; Riverpod async notifiers for async state in mobile
- **Secrets**: Never in `.env.example`. Encrypted in code via Jasypt (backend) or SharedPreferences + encryption (mobile)

---

## Common Tasks

### Add a new API endpoint
1. Create `src/my-feature/my-feature.controller.ts` + service
2. Define DTO for body/query validation
3. Register controller in `my-feature.module.ts`
4. Add tests (`*.spec.ts`)

### Add a new mobile screen
1. Create `lib/features/my_feature/my_feature_screen.dart`
2. Define Riverpod providers in `my_feature_providers.dart` if needed
3. Wire routing in `main.dart` or parent feature router
4. Add tests (`my_feature_screen_test.dart`)

### Deploy to OCI sandbox
```bash
./deploy.sh  # Pulls latest, runs docker compose build
```

### Database migration
```bash
cd backend
npx prisma migrate dev --name my_migration  # Create + apply
npx prisma migrate deploy                    # Apply in CI/prod
npx prisma generate                          # Regenerate client
```

---

## Vault / Decision Log

Active work & architecture decisions live in the project's Obsidian vault at:  
`02_work/projetos/sincro/` (status, roadmap, spec notes)

Key docs:
- `sincro_05_infraestrutura_sandbox_deploy.md` — OCI setup & deployment checklist
- `sincro_02_modulos_funcionalidades.md` — Feature status & roadmap

---

## Debugging Tips

- **Backend**: `npm run start:debug` then attach debugger to port 9229
- **Mobile**: `flutter run` with `-v` flag for verbose output; use DevTools (flutter devtools)
- **Postgres**: SSH tunnel to OCI: `ssh -L 5432:postgres:5432 ubuntu@<oci-ip> -N` then connect locally
- **Sentry**: Check sentry.io dashboard for backend/mobile error reports in real-time

---

## Related Skills & Tools

This project has project-scoped skills in `mobile/.claude/skills/`:
- `mobile:sincro-release` — Build & distribute Android release via Firebase App Distribution
- `mobile:design` — Design system & brand guidelines for the mobile app
- Others: UI styling, design tokens, brand guidelines

Invoke with `/skill-name` or via `Skill` tool.
