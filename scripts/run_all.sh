#!/usr/bin/env bash
# Orquestador end-to-end. Encadena los pasos del runbook que SI son
# automatizables, respetando las guardas FREEZE_*.
#
# Lo que sigue siendo manual y se documenta como 'PAUSE' al final:
#   - OAuth Authorize del provisioning (popup de Google).
#   - Test Connection (boton del portal de Entra).
#   - Asignacion del usuario de prueba (boton "Add user/group" del portal).
#   - Apply en Google y Start en Entra (PROHIBIDOS en esta sesion).
#
# Uso:
#   DRY_RUN=1 scripts/run_all.sh config/tenants/live.uem.es.vars
#   DRY_RUN=0 scripts/run_all.sh config/tenants/live.uem.es.vars
#
# Pre-requisitos:
#   - Secretos cargados en Cursor Dashboard segun docs/AUTOMATION_CREDENTIALS.md.
#   - GAM7 instalado.
#   - pwsh 7+ con modulo Microsoft.Graph.

set -euo pipefail

VARS_FILE="${1:-}"
DRY_RUN="${DRY_RUN:-1}"

if [[ -z "$VARS_FILE" ]]; then
  echo "uso: $0 <config/tenants/<dominio>.vars>" >&2
  exit 2
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

echo "=========================================================="
echo "Orquestador SSO+Provisioning  (DRY_RUN=$DRY_RUN)"
echo "vars: $VARS_FILE"
echo "=========================================================="

echo
echo "[0/6] Validando vars file"
python3 "$ROOT/scripts/common/validate_vars.py" "$VARS_FILE"

# shellcheck disable=SC1090
source "$VARS_FILE"

if [[ "$FREEZE_GOOGLE_SSO_TOGGLE" != "true" || "$FREEZE_ENTRA_PROVISIONING_START" != "true" ]]; then
  echo "ABORT: en esta sesion ambos FREEZE_* deben ser 'true'." >&2
  echo "  FREEZE_GOOGLE_SSO_TOGGLE=$FREEZE_GOOGLE_SSO_TOGGLE" >&2
  echo "  FREEZE_ENTRA_PROVISIONING_START=$FREEZE_ENTRA_PROVISIONING_START" >&2
  exit 5
fi

WHATIF_FLAG=()
if [[ "$DRY_RUN" == "1" ]]; then WHATIF_FLAG=(-WhatIf); fi

echo
echo "[1/6] Google -> OUs + usuario de servicio"
DRY_RUN="$DRY_RUN" bash "$ROOT/scripts/google/01_create_ous_and_service_user.sh" "$VARS_FILE"

echo
echo "[2/6] Google -> perfil SSO 'Entra ID' (sin asignar, OFF)"
DRY_RUN="$DRY_RUN" bash "$ROOT/scripts/google/02_create_sso_profile.sh" "$VARS_FILE"

echo
echo "[3/6] Entra -> Enterprise App (gallery)"
pwsh -NoLogo -File "$ROOT/scripts/common/connect_entra.ps1" -VarsFile "$VARS_FILE"
pwsh -NoLogo -File "$ROOT/scripts/entra/01_create_enterprise_app.ps1" \
  -VarsFile "$VARS_FILE" "${WHATIF_FLAG[@]}"

cat <<'EOF'

[3.5] CHECKPOINT MANUAL
  Exporta los IDs que el script anterior imprimio:
    export ENTRA_APP_OBJECT_ID='<value>'
    export ENTRA_SP_OBJECT_ID='<value>'
  Y copia la ACS URL del perfil SSO de Google:
    export ACS_URL_FROM_GOOGLE='<value>'
  Pulsa Enter para continuar (Ctrl-C para salir)...
EOF
read -r _

: "${ENTRA_APP_OBJECT_ID:?ENTRA_APP_OBJECT_ID no definido}"
: "${ENTRA_SP_OBJECT_ID:?ENTRA_SP_OBJECT_ID no definido}"
: "${ACS_URL_FROM_GOOGLE:?ACS_URL_FROM_GOOGLE no definido}"

echo
echo "[4/6] Entra -> SAML basic + claims + cert"
pwsh -NoLogo -File "$ROOT/scripts/common/connect_entra.ps1" -VarsFile "$VARS_FILE"
pwsh -NoLogo -File "$ROOT/scripts/entra/02_configure_saml.ps1" \
  -VarsFile "$VARS_FILE" \
  -AppObjectId "$ENTRA_APP_OBJECT_ID" \
  -ServicePrincipalId "$ENTRA_SP_OBJECT_ID" \
  -AcsUrlFromGoogle "$ACS_URL_FROM_GOOGLE" \
  "${WHATIF_FLAG[@]}"

cat <<'EOF'

[4.5] CHECKPOINT MANUAL
  Del portal Entra -> Set up panel, exporta:
    export AZURE_LOGIN_URL='<Login URL>'
    export AZURE_IDP_ENTITY_ID='<Microsoft Entra Identifier>'
  El cert se descargo como <dominio>-entraid-saml.cer en el cwd.
  Pulsa Enter para continuar...
EOF
read -r _

: "${AZURE_LOGIN_URL:?AZURE_LOGIN_URL no definido}"
: "${AZURE_IDP_ENTITY_ID:?AZURE_IDP_ENTITY_ID no definido}"

export AZURE_LOGIN_URL AZURE_IDP_ENTITY_ID
export AZURE_CERT_FILE="$PWD/${SAML_CERT_FILENAME}"

echo
echo "[5/6] Google -> cerrar el lazo en el perfil SSO (sin asignar OU)"
DRY_RUN="$DRY_RUN" bash "$ROOT/scripts/google/02_create_sso_profile.sh" "$VARS_FILE"

echo
echo "[6/6] Entra -> Provisioning (Automatic, mappings, NO Start)"
pwsh -NoLogo -File "$ROOT/scripts/common/connect_entra.ps1" -VarsFile "$VARS_FILE"
pwsh -NoLogo -File "$ROOT/scripts/entra/03_configure_provisioning.ps1" \
  -VarsFile "$VARS_FILE" \
  -ServicePrincipalId "$ENTRA_SP_OBJECT_ID" \
  "${WHATIF_FLAG[@]}"

cat <<EOF

==========================================================
Listo. Pasos manuales pendientes (NO los hace el orquestador):
  1) Entra portal -> app -> Provisioning -> Authorize
       (popup de Google: elegir $GOOGLE_SERVICE_ACCOUNT_USER, aceptar scopes).
  2) Provisioning -> Test Connection (debe devolver OK).
  3) Users and groups -> asignar 1 usuario de prueba.
  4) Esperar a que aparezca el analisis del grupo en Provisioning logs.
  5) STOP. NO pulsar Apply en Google. NO pulsar Start provisioning en Entra.
==========================================================
EOF
