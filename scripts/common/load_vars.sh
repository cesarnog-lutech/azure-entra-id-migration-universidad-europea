#!/usr/bin/env bash
# Carga un fichero de variables de tenant y valida campos minimos.
# Uso: source scripts/common/load_vars.sh config/tenants/<dominio>.vars
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "ERROR: uso: source $0 <ruta/al/tenant.vars>" >&2
  return 1 2>/dev/null || exit 1
fi

VARS_FILE="$1"

if [[ ! -f "$VARS_FILE" ]]; then
  echo "ERROR: no existe el fichero de variables: $VARS_FILE" >&2
  return 1 2>/dev/null || exit 1
fi

# shellcheck disable=SC1090
source "$VARS_FILE"

required=(
  TENANT_PRIMARY_DOMAIN
  TENANT_LABEL
  ENTRA_APP_DISPLAY_NAME
  GOOGLE_SSO_PROFILE_NAME
  GOOGLE_TEST_OU
  GOOGLE_LOCAL_LOGIN_OU
  GOOGLE_SYNC_USERS_OU
  GOOGLE_SERVICE_ACCOUNT_USER
  GOOGLE_ENTITY_ID
  GOOGLE_SIGN_ON_URL
  GOOGLE_SIGN_OUT_URL
  ORG_UNIT_PATH_CONSTANT
  SAML_CERT_FILENAME
  FREEZE_GOOGLE_SSO_TOGGLE
  FREEZE_ENTRA_PROVISIONING_START
)

missing=()
for v in "${required[@]}"; do
  if [[ -z "${!v:-}" ]]; then
    missing+=("$v")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "ERROR: variables vacias en $VARS_FILE: ${missing[*]}" >&2
  return 1 2>/dev/null || exit 1
fi

# Regla invariante: el orgUnitPath constante DEBE coincidir con /test SSO.
if [[ "$ORG_UNIT_PATH_CONSTANT" != "/test SSO" ]]; then
  echo "ERROR: ORG_UNIT_PATH_CONSTANT debe ser exactamente '/test SSO' en esta fase." >&2
  echo "       valor actual: '$ORG_UNIT_PATH_CONSTANT'" >&2
  return 1 2>/dev/null || exit 1
fi

echo "[load_vars] OK -> tenant=$TENANT_PRIMARY_DOMAIN label=$TENANT_LABEL"
