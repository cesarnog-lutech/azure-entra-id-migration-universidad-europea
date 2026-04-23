# azure-entra-id-migration-universidad-europea

Repositorio de configuración y runbooks para la migración / federación entre **Microsoft Entra ID** y **Google Workspace** en los tenants de Universidad Europea, en el marco del Acta de Proyecto UEM · Lutech v3.

## Contenido

- [`docs/runbooks/sso-provisioning-entra-google.md`](docs/runbooks/sso-provisioning-entra-google.md) — Runbook maestro **SSO + Provisioning (Entra ID ↔ Google Workspace)**. Replica las secciones 7 y 8 del Acta y aplica la regla de oro de la sesión actual: **NO habilitar SSO**, **NO pulsar Apply / Start provisioning**.
- [`docs/runbooks/tenants/`](docs/runbooks/tenants/) — Hojas de seguimiento por tenant.
  - [`live.uem.es.md`](docs/runbooks/tenants/live.uem.es.md) — Tenant en curso.
  - [`_TEMPLATE.md`](docs/runbooks/tenants/_TEMPLATE.md) — Plantilla para clonar a los próximos 2 tenants (TBD: CEG / UDI / Andorra / Portugal).
- [`config/tenants/`](config/tenants/) — Fichero de variables por tenant (fuente única de verdad para scripts y runbook).
  - [`live.uem.es.vars`](config/tenants/live.uem.es.vars)
  - [`_TEMPLATE.vars`](config/tenants/_TEMPLATE.vars)
- [`docs/AUTOMATION_CREDENTIALS.md`](docs/AUTOMATION_CREDENTIALS.md) — **Léelo primero si quieres ejecución desatendida.** Procedimiento para crear las credenciales mínimas (Google SA con DWD + Entra app registration), cargarlas como secretos del Cursor Cloud Agent, y rotarlas/revocarlas.
- [`scripts/`](scripts/) — Automatización idempotente (dry-run por defecto) para los pasos mecánicos:
  - [`scripts/run_all.sh`](scripts/run_all.sh) — orquestador end-to-end con checkpoints manuales mínimos.
  - [`scripts/common/validate_vars.py`](scripts/common/validate_vars.py) — validador offline de los ficheros de variables.
  - [`scripts/common/connect_entra.ps1`](scripts/common/connect_entra.ps1) — conexión no-interactiva a Microsoft Graph (client secret o cert).
  - [`scripts/common/bootstrap_gam_sa.sh`](scripts/common/bootstrap_gam_sa.sh) — materializa `oauth2service.json` de GAM7 desde el secreto.
  - [`scripts/google/01_create_ous_and_service_user.sh`](scripts/google/01_create_ous_and_service_user.sh) — GAM7.
  - [`scripts/google/02_create_sso_profile.sh`](scripts/google/02_create_sso_profile.sh) — GAM7 (respeta `FREEZE_GOOGLE_SSO_TOGGLE`).
  - [`scripts/entra/01_create_enterprise_app.ps1`](scripts/entra/01_create_enterprise_app.ps1) — Microsoft Graph PowerShell.
  - [`scripts/entra/02_configure_saml.ps1`](scripts/entra/02_configure_saml.ps1) — SAML + claims + certificado.
  - [`scripts/entra/03_configure_provisioning.ps1`](scripts/entra/03_configure_provisioning.ps1) — provisioning (respeta `FREEZE_ENTRA_PROVISIONING_START`).

## Ejecución desatendida desde Cursor Cloud Agent

1. Provisionar credenciales mínimas siguiendo [`docs/AUTOMATION_CREDENTIALS.md`](docs/AUTOMATION_CREDENTIALS.md).
2. Cargarlas como secretos en el dashboard de Cursor con los nombres `LIVE_UEM_ES_*` (un set por tenant).
3. Volver a invocar al Cloud Agent: ejecutará `scripts/run_all.sh config/tenants/live.uem.es.vars` y se detendrá en los 3 pasos que requieren clic humano (OAuth Authorize, Test Connection, asignación del usuario de prueba). Las dos líneas rojas (`SSO ON`, `Start provisioning`) permanecen bloqueadas por código mientras `FREEZE_*=true`.

## Convenciones

- Branches: `cursor/<descripcion>-<nnnn>`.
- Cualquier cambio de configuración debe reflejarse primero en el runbook correspondiente y, si aplica, en la hoja del tenant.
- Los valores que solo se conocen en runtime (Login URL de Azure, ACS URL de Google, certificados, etc.) se rellenan en la hoja del tenant — **no** en el runbook maestro.
