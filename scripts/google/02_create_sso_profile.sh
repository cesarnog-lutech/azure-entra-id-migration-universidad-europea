#!/usr/bin/env bash
# Paso 2 del runbook.
# Crea el perfil SSO de terceros "Entra ID" en Google Admin SIN asignarlo a
# ninguna OU y con el toggle en OFF. Respeta FREEZE_GOOGLE_SSO_TOGGLE=true.
#
# Dependencias:
#   - GAM7 autenticado como Super Admin del tenant objetivo.
#   - Si ya tenes los valores de Azure (paso 3), puede rellenarlos ahora;
#     si no, dejalos vacios y vuelve a correr este script como idempotente
#     tras ejecutar el paso 3.
#
# Uso:
#   DRY_RUN=1 AZURE_LOGIN_URL="" AZURE_IDP_ENTITY_ID="" AZURE_CERT_FILE="" \
#     scripts/google/02_create_sso_profile.sh config/tenants/live.uem.es.vars

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../common/load_vars.sh" "${1:-}"

DRY_RUN="${DRY_RUN:-1}"
GAM_BIN="${GAM_BIN:-gam}"
USE_SA="${USE_SA:-1}"

if [[ "$DRY_RUN" == "0" && "$USE_SA" == "1" && -z "${GAMCFGDIR:-}" ]]; then
  # shellcheck disable=SC1091
  source "$HERE/../common/bootstrap_gam_sa.sh" "${1:-}"
fi

AZURE_LOGIN_URL="${AZURE_LOGIN_URL:-}"
AZURE_IDP_ENTITY_ID="${AZURE_IDP_ENTITY_ID:-}"
AZURE_CERT_FILE="${AZURE_CERT_FILE:-}"

run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[DRY-RUN] %s\n' "$*"
  else
    printf '[RUN] %s\n' "$*"
    "$@"
  fi
}

if [[ "${FREEZE_GOOGLE_SSO_TOGGLE}" != "true" ]]; then
  echo "ERROR: FREEZE_GOOGLE_SSO_TOGGLE=${FREEZE_GOOGLE_SSO_TOGGLE}. En la sesion actual debe ser 'true'." >&2
  echo "       Si realmente estas en la sesion de activacion posterior, usa un script aparte." >&2
  exit 4
fi

echo "== Paso 2: perfil SSO Entra ID en Google =="
echo "   DRY_RUN: $DRY_RUN"
echo

# GAM soporta SSO third-party profiles con el comando "create inboundssoprofile".
# Dejamos el perfil sin asignaciones (no se pasa "enable" ni "assignedorgunits").
CMD=(
  "$GAM_BIN" create inboundssoprofile
  name "$GOOGLE_SSO_PROFILE_NAME"
  entityid "${AZURE_IDP_ENTITY_ID:-REPLACE_WITH_AZURE_IDP_ENTITY_ID}"
  loginurl "${AZURE_LOGIN_URL:-REPLACE_WITH_AZURE_LOGIN_URL}"
  logouturl "$GOOGLE_SIGN_OUT_URL"
  changepasswordurl "${PWM_CHANGE_PASSWORD_URL:-REPLACE_WITH_PWM_URL}"
)

if [[ -n "$AZURE_CERT_FILE" ]]; then
  CMD+=( certfile "$AZURE_CERT_FILE" )
fi

run "${CMD[@]}"

echo
echo "== Checkpoint =="
echo "   * El perfil SSO '$GOOGLE_SSO_PROFILE_NAME' debe aparecer en Admin Console"
echo "     (Security > Authentication > SSO with third-party IdPs)."
echo "   * NO asignarlo todavia a ninguna OU. Toggle debe permanecer en OFF."
echo "   * Apunta la ACS URL que muestra Google: se usa como Reply URL en Entra (paso 3)."
