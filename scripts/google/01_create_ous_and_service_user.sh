#!/usr/bin/env bash
# Paso 1 del runbook.
# Crea las OU /test SSO, /local_login, /Sync users y el usuario de servicio
# "Entra ID Conector" con rol Super Admin.
#
# Requisitos:
#   - GAM7 instalado y autenticado contra el tenant objetivo
#     (gam oauth create usando una cuenta Super Admin real del tenant).
#   - DRY_RUN=1 por defecto para evitar ejecuciones accidentales.
#
# Uso:
#   DRY_RUN=1 scripts/google/01_create_ous_and_service_user.sh config/tenants/live.uem.es.vars
#   DRY_RUN=0 scripts/google/01_create_ous_and_service_user.sh config/tenants/live.uem.es.vars

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../common/load_vars.sh" "${1:-}"

DRY_RUN="${DRY_RUN:-1}"
GAM_BIN="${GAM_BIN:-gam}"
USE_SA="${USE_SA:-1}"

run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[DRY-RUN] %s\n' "$*"
  else
    printf '[RUN] %s\n' "$*"
    "$@"
  fi
}

echo "== Paso 1: OUs + usuario de servicio =="
echo "   tenant  : $TENANT_PRIMARY_DOMAIN"
echo "   DRY_RUN : $DRY_RUN"
echo "   USE_SA  : $USE_SA"
echo

if [[ "$DRY_RUN" == "0" ]]; then
  if ! command -v "$GAM_BIN" >/dev/null 2>&1; then
    echo "ERROR: GAM no disponible en PATH ('$GAM_BIN'). Instalar GAM7 primero." >&2
    exit 2
  fi
  if [[ "$USE_SA" == "1" && -z "${GAMCFGDIR:-}" ]]; then
    # shellcheck disable=SC1091
    source "$HERE/../common/bootstrap_gam_sa.sh" "${1:-}"
  fi
  echo "[check] verificando que GAM puede leer info del dominio $TENANT_PRIMARY_DOMAIN"
  "$GAM_BIN" info domain 2>/dev/null | grep -i "$TENANT_PRIMARY_DOMAIN" >/dev/null || {
    echo "ERROR: GAM no puede consultar el dominio $TENANT_PRIMARY_DOMAIN (auth o DWD insuficiente)." >&2
    exit 3
  }
fi

run "$GAM_BIN" create org "${GOOGLE_TEST_OU#/}" description "Ambito acotado de pruebas SSO/Provisioning Entra ID - Lutech"
run "$GAM_BIN" create org "${GOOGLE_LOCAL_LOGIN_OU#/}" description "Cuentas locales / servicio sin SSO"
run "$GAM_BIN" create org "${GOOGLE_SYNC_USERS_OU#/}" description "OU contenedora de la cuenta de servicio Entra ID Conector"

SVC_PASS="$(openssl rand -base64 24 2>/dev/null || true)"
if [[ -z "$SVC_PASS" ]]; then
  SVC_PASS="$(date +%s%N | sha256sum | head -c 24)Aa1!"
fi

run "$GAM_BIN" create user "$GOOGLE_SERVICE_ACCOUNT_USER" \
  firstname "$GOOGLE_SERVICE_ACCOUNT_GIVEN_NAME" \
  lastname "$GOOGLE_SERVICE_ACCOUNT_FAMILY_NAME" \
  password "$SVC_PASS" \
  changepassword false \
  org "${GOOGLE_SYNC_USERS_OU#/}"

run "$GAM_BIN" user "$GOOGLE_SERVICE_ACCOUNT_USER" add role "_SEED_ADMIN_ROLE"

if [[ "$DRY_RUN" == "0" ]]; then
  echo
  echo "ACCION MANUAL: guarda esta password de servicio en el gestor corporativo AHORA:"
  echo "    usuario: $GOOGLE_SERVICE_ACCOUNT_USER"
  echo "    password: $SVC_PASS"
  echo
fi

echo
echo "== Listo. Verifica en Admin Console que las 3 OU existen y que $GOOGLE_SERVICE_ACCOUNT_USER tiene Super Admin. =="
