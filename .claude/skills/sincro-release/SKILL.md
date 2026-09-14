---
name: sincro-release
description: "Realiza o build da release Android do app Sincro e distribui via Firebase App Distribution para o grupo de testadores. Suporta bump de versão (patch/minor/major), notas de lançamento e parâmetros de ambiente."
argument-hint: "[-b patch|minor|major|build] [-m 'notas'] [-g 'grupos']"
---

# Sincro Release Agent

Agente especializado no build e distribuição de releases do app mobile Sincro (Flutter) para o Firebase App Distribution.

## Pré-requisitos Verificados
- Diretório mobile: `mobile/`
- Script de automação: `scripts/release-firebase.sh` (ou `mobile/scripts/release-firebase.sh`)
- Firebase App ID: `1:393611506422:android:f864f79df7084de28972d7` (Projeto `sincro-3ac01`)
- Grupo padrão de testadores: `testadores-sandbox`
- Keystore configurado em `mobile/android/key.properties` e `mobile/android/app/release-key.jks`

## Como Executar

### 1. Build com bump automático de versão (ex: patch) e notas:
```bash
./scripts/release-firebase.sh -b patch -m "Correções e melhorias de estabilidade"
```

### 2. Definindo versão manualmente:
```bash
./scripts/release-firebase.sh -v 1.0.5+2 -m "Versão 1.0.5 liberada para testes"
```

### 3. Apenas build (Dry-run, sem enviar ao Firebase):
```bash
./scripts/release-firebase.sh -b patch --dry-run
```

### 4. Distribuir APK já compilado:
```bash
./scripts/release-firebase.sh --skip-build -m "Reteste da versão atual"
```

## Opções do Script
- `-b, --bump <patch|minor|major|build>`: Incrementa versão no `pubspec.yaml`
- `-v, --version <x.y.z+n>`: Define versão específica
- `-m, --notes <texto>`: Notas de lançamento no Firebase
- `-g, --groups <nome>`: Grupos de testadores (padrão: `testadores-sandbox`)
- `-u, --api-url <url>`: URL base da API (padrão: `https://sincro-sandbox.duckdns.org/api`)
- `--client-id <id>`: Google OAuth Web Client ID para Gmail
- `--sentry-dsn <dsn>`: DSN do Sentry para rastreamento de erros
