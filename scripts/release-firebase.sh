#!/usr/bin/env bash
# Encaminha a chamada para o script mobile/scripts/release-firebase.sh
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "${ROOT_DIR}/mobile/scripts/release-firebase.sh" "$@"
