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
