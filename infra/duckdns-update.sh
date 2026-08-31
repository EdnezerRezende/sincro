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
