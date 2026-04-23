#!/usr/bin/env bash
# Materializa el oauth2service.json de GAM7 a partir del secreto del Cloud Agent
# y prepara el subject de impersonacion. Permite que GAM7 funcione sin
# 'gam oauth create' interactivo.
#
# Espera variables de entorno (inyectadas por Cursor Dashboard -> Secrets):
#   <PREFIX>_GOOGLE_SA_JSON                -> contenido completo del JSON de la SA
#   <PREFIX>_GOOGLE_IMPERSONATE_SUBJECT    -> usuario admin a impersonar
#
# <PREFIX> deriva de TENANT_LABEL en el vars file: live-uem-es -> LIVE_UEM_ES
#
# Uso:
#   source scripts/common/bootstrap_gam_sa.sh config/tenants/live.uem.es.vars
#
# Tras ejecutarlo:
#   - $GAMCFGDIR queda apuntando a un dir temporal con oauth2service.json + client_secrets.json (vacio)
#   - GAM7 usa la SA por defecto.
#   - Cualquier llamada gam usa el subject indicado.

set -euo pipefail

if [[ "${BASH_SOURCE[0]:-}" == "$0" ]]; then
  echo "ERROR: este script debe ser sourced (source $0 ...), no ejecutado." >&2
  exit 1
fi

VARS_FILE="${1:-}"
if [[ -z "$VARS_FILE" || ! -f "$VARS_FILE" ]]; then
  echo "ERROR: ruta vars no valida: '$VARS_FILE'" >&2
  return 1
fi

# shellcheck disable=SC1090
source "$VARS_FILE"

if [[ -z "${TENANT_LABEL:-}" ]]; then
  echo "ERROR: TENANT_LABEL vacio en $VARS_FILE" >&2
  return 1
fi

prefix="$(echo "$TENANT_LABEL" | tr 'a-z-' 'A-Z_')"
sa_json_var="${prefix}_GOOGLE_SA_JSON"
subject_var="${prefix}_GOOGLE_IMPERSONATE_SUBJECT"

sa_json="${!sa_json_var:-}"
subject="${!subject_var:-}"

if [[ -z "$sa_json" ]]; then
  echo "ERROR: secreto $sa_json_var no esta definido. Subelo en Cursor Dashboard -> Cloud Agents -> Secrets." >&2
  return 1
fi
if [[ -z "$subject" ]]; then
  echo "ERROR: secreto $subject_var no esta definido (usuario admin a impersonar)." >&2
  return 1
fi

if ! command -v gam >/dev/null 2>&1; then
  echo "ERROR: GAM7 no esta instalado en PATH." >&2
  return 1
fi

cfgdir="$(mktemp -d -t gamcfg.${TENANT_LABEL}.XXXXXX)"
chmod 700 "$cfgdir"
umask 077

printf '%s' "$sa_json" > "$cfgdir/oauth2service.json"
chmod 600 "$cfgdir/oauth2service.json"

if ! python3 -c "import json,sys; json.load(open('$cfgdir/oauth2service.json'))" 2>/dev/null; then
  echo "ERROR: el contenido de $sa_json_var no es JSON valido." >&2
  rm -rf "$cfgdir"
  return 1
fi

printf '{}\n' > "$cfgdir/client_secrets.json"
chmod 600 "$cfgdir/client_secrets.json"

export GAMCFGDIR="$cfgdir"
export GAM_OAUTH_SUBJECT="$subject"

dom_in_sa="$(python3 -c "import json; d=json.load(open('$cfgdir/oauth2service.json')); print(d.get('client_email',''))")"
echo "[bootstrap-gam-sa] OK"
echo "  tenant      : $TENANT_PRIMARY_DOMAIN"
echo "  GAMCFGDIR   : $cfgdir"
echo "  SA email    : $dom_in_sa"
echo "  subject     : $subject"
echo "  uso recomendado: 'gam user $subject ...'  o  'gam create user --asadmin $subject ...'"
