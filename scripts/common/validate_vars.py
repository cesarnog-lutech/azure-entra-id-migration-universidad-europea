#!/usr/bin/env python3
"""Validador del fichero de variables de tenant.

Comprueba sin tocar Google ni Entra que:
  - Los campos obligatorios estan presentes.
  - Las URLs derivadas son consistentes con TENANT_PRIMARY_DOMAIN.
  - El orgUnitPath constante es exactamente "/test SSO".
  - El dominio es un FQDN aceptable.
  - Los freezes de la sesion estan en el valor correcto ("true").

Uso:
    python3 scripts/common/validate_vars.py config/tenants/live.uem.es.vars

Sale con codigo 0 si todo OK, !=0 si hay errores.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Dict, List

REQUIRED = [
    "TENANT_PRIMARY_DOMAIN",
    "TENANT_LABEL",
    "ENTRA_APP_DISPLAY_NAME",
    "GOOGLE_SSO_PROFILE_NAME",
    "GOOGLE_TEST_OU",
    "GOOGLE_LOCAL_LOGIN_OU",
    "GOOGLE_SYNC_USERS_OU",
    "GOOGLE_SERVICE_ACCOUNT_USER",
    "GOOGLE_ENTITY_ID",
    "GOOGLE_SIGN_ON_URL",
    "GOOGLE_SIGN_OUT_URL",
    "ORG_UNIT_PATH_CONSTANT",
    "SAML_CERT_FILENAME",
    "FREEZE_GOOGLE_SSO_TOGGLE",
    "FREEZE_ENTRA_PROVISIONING_START",
]

EXPECTED_CONSTANTS = {
    "ENTRA_APP_DISPLAY_NAME": "Google Cloud / G Suite Connector by Microsoft",
    "GOOGLE_SSO_PROFILE_NAME": "Entra ID",
    "GOOGLE_TEST_OU": "/test SSO",
    "GOOGLE_LOCAL_LOGIN_OU": "/local_login",
    "GOOGLE_SYNC_USERS_OU": "/Sync users",
    "GOOGLE_SIGN_OUT_URL": "https://login.microsoftonline.com/common/wsfederation?wa=wsignout1.0",
    "ORG_UNIT_PATH_CONSTANT": "/test SSO",
    "FREEZE_GOOGLE_SSO_TOGGLE": "true",
    "FREEZE_ENTRA_PROVISIONING_START": "true",
}

VAR_RE = re.compile(r"^\s*([A-Z_][A-Z0-9_]*)\s*=\s*\"?(.*?)\"?\s*$")
INTERP_RE = re.compile(r"\$\{([A-Z_][A-Z0-9_]*)\}")
FQDN_RE = re.compile(r"^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$")


def parse_vars(path: Path) -> Dict[str, str]:
    out: Dict[str, str] = {}
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        m = VAR_RE.match(line)
        if not m:
            continue
        name, val = m.group(1), m.group(2)
        val = INTERP_RE.sub(lambda mm: out.get(mm.group(1), ""), val)
        out[name] = val
    return out


def validate(path: Path) -> List[str]:
    errors: List[str] = []
    if not path.is_file():
        return [f"vars file no existe: {path}"]

    vars_ = parse_vars(path)

    for r in REQUIRED:
        if not vars_.get(r):
            errors.append(f"campo obligatorio vacio: {r}")

    for k, expected in EXPECTED_CONSTANTS.items():
        actual = vars_.get(k, "")
        if actual != expected:
            errors.append(f"{k} debe ser exactamente '{expected}' (actual: '{actual}')")

    dom = vars_.get("TENANT_PRIMARY_DOMAIN", "")
    if dom and not FQDN_RE.match(dom):
        errors.append(f"TENANT_PRIMARY_DOMAIN no es un FQDN valido: '{dom}'")

    expect_entity = f"google.com/a/{dom}"
    if vars_.get("GOOGLE_ENTITY_ID") != expect_entity:
        errors.append(
            f"GOOGLE_ENTITY_ID debe ser '{expect_entity}' (actual: '{vars_.get('GOOGLE_ENTITY_ID')}')"
        )

    expect_sign_on = (
        f"https://www.google.com/a/{dom}/ServiceLogin?continue=https://console.cloud.google.com/"
    )
    if vars_.get("GOOGLE_SIGN_ON_URL") != expect_sign_on:
        errors.append(
            f"GOOGLE_SIGN_ON_URL no coincide con el esperado para el dominio.\n"
            f"  esperado: {expect_sign_on}\n  actual:   {vars_.get('GOOGLE_SIGN_ON_URL')}"
        )

    sa = vars_.get("GOOGLE_SERVICE_ACCOUNT_USER", "")
    if dom and sa and not sa.endswith("@" + dom):
        errors.append(
            f"GOOGLE_SERVICE_ACCOUNT_USER deberia terminar en @{dom} (actual: '{sa}')"
        )

    cert = vars_.get("SAML_CERT_FILENAME", "")
    if dom and cert and not cert.startswith(dom + "-"):
        errors.append(
            f"SAML_CERT_FILENAME deberia empezar con '{dom}-' (actual: '{cert}')"
        )

    return errors


def main(argv: List[str]) -> int:
    if len(argv) != 2:
        print("uso: validate_vars.py <ruta/al/tenant.vars>", file=sys.stderr)
        return 2
    path = Path(argv[1])
    errors = validate(path)
    if errors:
        print(f"FAIL: {path} tiene {len(errors)} error(es):", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1
    print(f"OK: {path} valido.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
