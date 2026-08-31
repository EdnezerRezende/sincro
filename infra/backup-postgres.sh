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
