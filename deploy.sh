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
