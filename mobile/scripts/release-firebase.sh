#!/usr/bin/env bash
# ==============================================================================
# Sincro Mobile - Build Release & Firebase App Distribution Deploy
# ==============================================================================
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Determine project roots
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../pubspec.yaml" ]]; then
  MOBILE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
  PROJECT_ROOT="$(cd "${MOBILE_DIR}/.." && pwd)"
elif [[ -f "${SCRIPT_DIR}/pubspec.yaml" ]]; then
  MOBILE_DIR="${SCRIPT_DIR}"
  PROJECT_ROOT="$(cd "${MOBILE_DIR}/.." && pwd)"
else
  echo -e "${RED}Erro: Não foi possível localizar o diretório 'mobile/' com pubspec.yaml${NC}" >&2
  exit 1
fi

# Default configuration
FIREBASE_APP_ID="1:393611506422:android:f864f79df7084de28972d7"
DEFAULT_GROUPS="testadores-sandbox"
DEFAULT_API_URL="https://sincro-sandbox.duckdns.org/api"
DEFAULT_GOOGLE_CLIENT_ID="393611506422-g0ufsk76bb8kk4krc7g2tvg9uipibr6c.apps.googleusercontent.com"

VERSION_OVERRIDE=""
BUMP_TYPE=""
RELEASE_NOTES=""
RELEASE_NOTES_FILE=""
TESTER_GROUPS="${DEFAULT_GROUPS}"
API_BASE_URL="${DEFAULT_API_URL}"
GOOGLE_CLIENT_ID="${DEFAULT_GOOGLE_CLIENT_ID}"
SENTRY_DSN=""
SKIP_BUILD=false
DRY_RUN=false

show_help() {
  cat <<EOF
Uso: $(basename "$0") [opções]

Realiza o build da release Android do Sincro Mobile e distribui via Firebase App Distribution.

Opções:
  -v, --version <versão>        Define manualmente a versão (ex: 1.0.5+2) no pubspec.yaml
  -b, --bump <tipo>             Incrementa versão: patch, minor, major ou build
  -m, --notes <texto>           Notas de lançamento para os testadores
  -f, --notes-file <arquivo>    Lê as notas de lançamento a partir de um arquivo
  -g, --groups <grupos>         Grupos de testadores no Firebase (padrão: ${DEFAULT_GROUPS})
  -u, --api-url <url>           URL base da API backend (padrão: ${DEFAULT_API_URL})
      --client-id <id>          Google Web Client ID para OAuth Gmail
      --sentry-dsn <dsn>        DSN do Sentry para crash reporting (opcional)
      --skip-build              Pula o build e distribui o APK existente
      --dry-run                 Executa apenas o build, sem enviar ao Firebase
  -h, --help                    Exibe esta ajuda

Exemplos:
  $(basename "$0") -b patch -m "Correção no fluxo de biofeedback e onboarding"
  $(basename "$0") -v 1.1.0+5 -m "Nova tela de finanças conectada ao Pluggy"
  $(basename "$0") --skip-build -m "Reteste da versão atual"
EOF
}

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--version)
      VERSION_OVERRIDE="$2"
      shift 2
      ;;
    -b|--bump)
      BUMP_TYPE="$2"
      shift 2
      ;;
    -m|--notes)
      RELEASE_NOTES="$2"
      shift 2
      ;;
    -f|--notes-file)
      RELEASE_NOTES_FILE="$2"
      shift 2
      ;;
    -g|--groups)
      TESTER_GROUPS="$2"
      shift 2
      ;;
    -u|--api-url)
      API_BASE_URL="$2"
      shift 2
      ;;
    --client-id)
      GOOGLE_CLIENT_ID="$2"
      shift 2
      ;;
    --sentry-dsn)
      SENTRY_DSN="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo -e "${RED}Opção desconhecida: $1${NC}" >&2
      show_help
      exit 1
      ;;
  esac
done

cd "${MOBILE_DIR}"

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}   Sincro Release & Firebase App Distribution        ${NC}"
echo -e "${BLUE}======================================================${NC}"

# Check prerequisites
echo -e "\n${YELLOW}==> 1. Verificando pré-requisitos...${NC}"

if ! command -v flutter &>/dev/null; then
  echo -e "${RED}Erro: Flutter SDK não encontrado no PATH.${NC}" >&2
  exit 1
fi
echo -e "  [✓] Flutter SDK: $(flutter --version | head -n 1)"

if ! command -v firebase &>/dev/null; then
  echo -e "${RED}Erro: Firebase CLI (firebase-tools) não encontrada no PATH.${NC}" >&2
  echo -e "${YELLOW}Instale via: npm install -g firebase-tools${NC}" >&2
  exit 1
fi
echo -e "  [✓] Firebase CLI: $(firebase --version)"

KEY_PROPERTIES="${MOBILE_DIR}/android/key.properties"
KEYSTORE_FILE="${MOBILE_DIR}/android/app/release-key.jks"

if [[ ! -f "${KEY_PROPERTIES}" ]]; then
  echo -e "${RED}Erro: Arquivo '${KEY_PROPERTIES}' não encontrado!${NC}" >&2
  exit 1
fi
if [[ ! -f "${KEYSTORE_FILE}" ]]; then
  echo -e "${RED}Erro: Keystore de release '${KEYSTORE_FILE}' não encontrado!${NC}" >&2
  exit 1
fi
echo -e "  [✓] Keystore de release configurado."

# Version resolution & bumping
echo -e "\n${YELLOW}==> 2. Gerenciando versão do app...${NC}"

PUBSPEC_FILE="${MOBILE_DIR}/pubspec.yaml"
CURRENT_VERSION_LINE=$(grep "^version:" "${PUBSPEC_FILE}")
CURRENT_VERSION=$(echo "${CURRENT_VERSION_LINE}" | awk '{print $2}')
echo -e "  Versão atual no pubspec.yaml: ${GREEN}${CURRENT_VERSION}${NC}"

TARGET_VERSION="${CURRENT_VERSION}"

if [[ -n "${VERSION_OVERRIDE}" ]]; then
  TARGET_VERSION="${VERSION_OVERRIDE}"
  echo -e "  Atualizando versão para: ${GREEN}${TARGET_VERSION}${NC}"
  sed -i '' "s/^version: .*/version: ${TARGET_VERSION}/" "${PUBSPEC_FILE}"
elif [[ -n "${BUMP_TYPE}" ]]; then
  # Split version into name and build number
  VERSION_NAME="${CURRENT_VERSION%+*}"
  BUILD_NUM="${CURRENT_VERSION#*+}"
  if [[ "${BUILD_NUM}" == "${CURRENT_VERSION}" ]]; then
    BUILD_NUM=1
  fi

  IFS='.' read -r MAJOR MINOR PATCH <<< "${VERSION_NAME}"
  MAJOR=${MAJOR:-1}
  MINOR=${MINOR:-0}
  PATCH=${PATCH:-0}

  case "${BUMP_TYPE}" in
    major)
      MAJOR=$((MAJOR + 1))
      MINOR=0
      PATCH=0
      BUILD_NUM=$((BUILD_NUM + 1))
      ;;
    minor)
      MINOR=$((MINOR + 1))
      PATCH=0
      BUILD_NUM=$((BUILD_NUM + 1))
      ;;
    patch)
      PATCH=$((PATCH + 1))
      BUILD_NUM=$((BUILD_NUM + 1))
      ;;
    build)
      BUILD_NUM=$((BUILD_NUM + 1))
      ;;
    *)
      echo -e "${RED}Tipo de bump inválido: '${BUMP_TYPE}'. Escolha: major, minor, patch, build.${NC}" >&2
      exit 1
      ;;
  esac

  TARGET_VERSION="${MAJOR}.${MINOR}.${PATCH}+${BUILD_NUM}"
  echo -e "  Incrementando versão (${BUMP_TYPE}) para: ${GREEN}${TARGET_VERSION}${NC}"
  sed -i '' "s/^version: .*/version: ${TARGET_VERSION}/" "${PUBSPEC_FILE}"
fi

# Release notes resolution
if [[ -n "${RELEASE_NOTES_FILE}" && -f "${RELEASE_NOTES_FILE}" ]]; then
  RELEASE_NOTES=$(cat "${RELEASE_NOTES_FILE}")
elif [[ -z "${RELEASE_NOTES}" ]]; then
  # Fallback to last git commit message if inside a git repo
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    LAST_COMMIT=$(git log -1 --pretty=format:"%s")
    RELEASE_NOTES="Versão ${TARGET_VERSION}: ${LAST_COMMIT}"
  else
    RELEASE_NOTES="Versão ${TARGET_VERSION}"
  fi
fi

echo -e "  Notas de lançamento: ${YELLOW}${RELEASE_NOTES}${NC}"

# Build Step
APK_PATH="${MOBILE_DIR}/build/app/outputs/flutter-apk/app-release.apk"

if [[ "${SKIP_BUILD}" == true ]]; then
  echo -e "\n${YELLOW}==> 3. Pula build solicitado (--skip-build). Verificando APK existente...${NC}"
  if [[ ! -f "${APK_PATH}" ]]; then
    echo -e "${RED}Erro: APK não encontrado em '${APK_PATH}'. Execute sem --skip-build primeiro.${NC}" >&2
    exit 1
  fi
else
  echo -e "\n${YELLOW}==> 3. Executando build da release (Flutter APK)...${NC}"
  echo -e "  Configurações de ambiente:"
  echo -e "    - API_BASE_URL: ${API_BASE_URL}"
  echo -e "    - GOOGLE_WEB_CLIENT_ID: ${GOOGLE_CLIENT_ID}"
  if [[ -n "${SENTRY_DSN}" ]]; then
    echo -e "    - SENTRY_DSN: [configurado]"
  fi

  echo -e "  Executando 'flutter pub get'..."
  flutter pub get

  BUILD_CMD=(
    flutter build apk --release
    "--dart-define=API_BASE_URL=${API_BASE_URL}"
    "--dart-define=GOOGLE_WEB_CLIENT_ID=${GOOGLE_CLIENT_ID}"
  )

  if [[ -n "${SENTRY_DSN}" ]]; then
    BUILD_CMD+=("--dart-define=SENTRY_DSN=${SENTRY_DSN}")
  fi

  echo -e "  Compilando: ${BUILD_CMD[*]}..."
  "${BUILD_CMD[@]}"

  if [[ ! -f "${APK_PATH}" ]]; then
    echo -e "${RED}Erro: Build finalizado mas APK não foi encontrado em '${APK_PATH}'!${NC}" >&2
    exit 1
  fi
fi

APK_SIZE=$(ls -lh "${APK_PATH}" | awk '{print $5}')
echo -e "  ${GREEN}[✓] APK Release pronto: ${APK_PATH} (${APK_SIZE})${NC}"

# Firebase App Distribution Step
if [[ "${DRY_RUN}" == true ]]; then
  echo -e "\n${YELLOW}==> 4. Modo Dry Run ativado. Envio ao Firebase ignorado.${NC}"
else
  echo -e "\n${YELLOW}==> 4. Distribuindo via Firebase App Distribution...${NC}"
  echo -e "  App ID: ${FIREBASE_APP_ID}"
  echo -e "  Grupos: ${TESTER_GROUPS}"

  firebase appdistribution:distribute "${APK_PATH}" \
    --app "${FIREBASE_APP_ID}" \
    --groups "${TESTER_GROUPS}" \
    --release-notes "${RELEASE_NOTES}"

  echo -e "\n${GREEN}[✓] Release distribuída com sucesso no Firebase!${NC}"
fi

echo -e "\n${BLUE}======================================================${NC}"
echo -e "${GREEN}Processo concluído com sucesso! (Versão: ${TARGET_VERSION})${NC}"
echo -e "${BLUE}======================================================${NC}"
