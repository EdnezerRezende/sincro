#!/usr/bin/env bash
# Reimplanta o ambiente sandbox: puxa a última versão do branch atual e reconstrói os
# containers que mudaram. Rodar via SSH, de dentro do diretório onde o repo foi clonado na VPS
# (ver Task 8 — "Preparar VPS").
set -euo pipefail

cd "$(dirname "$0")"

echo "==> git pull"
# --ff-only: se a cópia da VPS divergiu da master, falha em vez de criar um merge local.
git pull --ff-only

echo "==> docker compose up -d --build"
docker compose -f docker-compose.yml -f docker-compose.sandbox.yml up -d --build

echo "==> containers ativos:"
docker compose -f docker-compose.yml -f docker-compose.sandbox.yml ps

# Remove imagens antigas que cada build deixa para trás; o disco da VPS gratuita é pequeno.
echo "==> limpando imagens não usadas"
docker image prune -f

echo "==> deploy concluído"
