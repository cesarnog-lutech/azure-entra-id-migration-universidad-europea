# azure-entra-id-migration-universidad-europea

Repositorio de configuración y runbooks para la migración / federación entre **Microsoft Entra ID** y **Google Workspace** en los tenants de Universidad Europea, en el marco del Acta de Proyecto UEM · Lutech v3.

## Contenido

- [`docs/runbooks/sso-provisioning-entra-google.md`](docs/runbooks/sso-provisioning-entra-google.md) — Runbook maestro **SSO + Provisioning (Entra ID ↔ Google Workspace)**. Replica las secciones 7 y 8 del Acta y aplica la regla de oro de la sesión actual: **NO habilitar SSO**, **NO pulsar Apply / Start provisioning**.
- [`docs/runbooks/tenants/`](docs/runbooks/tenants/) — Hojas de seguimiento por tenant.
  - [`live.uem.es.md`](docs/runbooks/tenants/live.uem.es.md) — Tenant en curso.
  - [`_TEMPLATE.md`](docs/runbooks/tenants/_TEMPLATE.md) — Plantilla para clonar a los próximos 2 tenants (TBD: CEG / UDI / Andorra / Portugal).

## Convenciones

- Branches: `cursor/<descripcion>-<nnnn>`.
- Cualquier cambio de configuración debe reflejarse primero en el runbook correspondiente y, si aplica, en la hoja del tenant.
- Los valores que solo se conocen en runtime (Login URL de Azure, ACS URL de Google, certificados, etc.) se rellenan en la hoja del tenant — **no** en el runbook maestro.
