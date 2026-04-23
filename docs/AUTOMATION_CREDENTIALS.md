# Credenciales para automatización end-to-end

> **TL;DR.** El agente no puede "encontrar" credenciales: hay que *crearlas* explícitamente, mínimas, y registrarlas como secretos del Cloud Agent en Cursor. Las credenciales viven solo ahí; nunca en el repo, nunca en el runbook, nunca en variables planas. Las guardas `FREEZE_*` siguen activas: incluso con credenciales válidas, el agente NO encenderá SSO ni arrancará el provisioning en esta sesión.

Este documento describe **exactamente** qué hay que crear, con qué scopes, en qué consola, y cómo subirlo a [cursor.com/dashboard](https://cursor.com/dashboard) → *Cloud Agents → Secrets*. Aplica para cada uno de los 3 tenants (`live.uem.es` y los 2 TBD).

---

## 1. Modelo de seguridad

Tres principios no negociables:

1. **Mínimo privilegio por superficie**:
   - Google Workspace → cuenta de servicio dedicada con **Domain-Wide Delegation** acotada a los scopes OAuth listados en §3.4. Nada más.
   - Entra ID → app registration dedicada con permisos *application* del Microsoft Graph listados en §4.4. Nada más.
2. **Aislamiento por tenant**: un set de secretos por tenant, prefijado por `TENANT_LABEL` (ej. `LIVE_UEM_ES_*`). Nunca compartir entre tenants.
3. **Reversibilidad inmediata**: cualquier credencial creada para esto debe poder revocarse en 30 segundos desde Google Admin (deshabilitar la SA) y desde Entra (revocar la client secret de la app registration). Documentar el procedimiento en este mismo archivo (§7).

Las guardas `FREEZE_GOOGLE_SSO_TOGGLE=true` y `FREEZE_ENTRA_PROVISIONING_START=true` del fichero de variables del tenant impiden que cualquier ejecución, autenticada o no, cruce las dos líneas rojas de la sesión actual (subir el toggle SSO en Google y arrancar el sync job en Entra).

---

## 2. Aprobaciones requeridas antes de empezar

- [ ] Aprobación escrita de UEM IT (Alejandro Serrano) para crear:
  - Una cuenta de servicio Google con Domain-Wide Delegation en el tenant `live.uem.es`.
  - Una app registration en Entra ID `live.uem.es` con los permisos *application* listados.
- [ ] Confirmación de que la responsabilidad operativa de rotar estos secretos queda en Lutech (recomendado: 90 días, ver §6).

Sin estas dos aprobaciones, no continuar.

---

## 3. Google Workspace — Cuenta de servicio (vía GCP) con Domain-Wide Delegation

### 3.1 Crear el proyecto GCP "host"

Cualquier proyecto GCP sirve para alojar la cuenta de servicio; no tiene por qué ser facturable, pero se recomienda uno dedicado (`uem-sso-automation-prod`) para auditar el ciclo de vida de la SA por separado de proyectos de producto.

```
GCP Console → Manage resources → Create Project
  Name:     uem-sso-automation-prod
  Org:      <organización GCP de UEM si existe; en su defecto, sin org>
```

### 3.2 Habilitar la Admin SDK API

```
APIs & Services → Library → "Admin SDK API" → Enable
APIs & Services → Library → "Identity and Access Management (IAM) API" → Enable
```

### 3.3 Crear la cuenta de servicio

```
IAM & Admin → Service Accounts → Create service account
  Name:        uem-sso-automation
  Description: SA usada por la automatización Cursor para provisioning Entra ID ↔ Google Workspace
  Roles GCP:   (ninguno — la SA no necesita permisos GCP)
```

Después de crearla:

```
Service account → Keys → Add Key → Create new key → JSON
  → descarga el fichero, GUÁRDALO solo en el gestor corporativo;
    se subirá una sola vez como secreto del Cloud Agent (§5).
```

Anota el **Unique ID (numérico)** y el **email** de la SA — los necesitarás en §3.4.

### 3.4 Habilitar Domain-Wide Delegation y autorizar scopes en Google Admin

En la propia ficha de la SA: *Show domain-wide delegation* → marca **Enable G Suite Domain-wide Delegation** → guarda.

Después, en **Google Admin Console** del tenant `live.uem.es`:

```
Security → Access and data control → API controls
  → Manage Domain Wide Delegation
  → Add new
       Client ID:  <Unique ID numérico de la SA del paso 3.3>
       OAuth scopes (lista exacta, separados por coma):
         https://www.googleapis.com/auth/admin.directory.user
         https://www.googleapis.com/auth/admin.directory.group
         https://www.googleapis.com/auth/admin.directory.orgunit
         https://www.googleapis.com/auth/admin.directory.rolemanagement
         https://www.googleapis.com/auth/admin.directory.userschema
         https://www.googleapis.com/auth/cloud-identity.inboundsso
       → Authorize
```

> Si aparece el error **`admin_policy_enforced`** durante una llamada posterior, suele ser un scope mal copiado o la propagación aún no completada (puede tardar varios minutos). Reintentar.

### 3.5 Designar el "subject" (usuario admin que la SA va a *impersonar*)

GAM7 con cuenta de servicio requiere impersonar a una cuenta humana Super Admin. Recomendación: usar el usuario `entra-id-conector@live.uem.es` que crea el script `01_create_ous_and_service_user.sh` (con rol Super Admin asignado por ese mismo script). Mientras esa cuenta no exista todavía, el bootstrap inicial debe hacerse impersonando a un Super Admin humano de UEM (registrar en log quién, cuándo y por qué).

Anota el `subject` final: `entra-id-conector@live.uem.es`.

---

## 4. Microsoft Entra ID — App registration

### 4.1 Crear la app

```
Entra admin center → Applications → App registrations → New registration
  Name:                uem-sso-automation
  Supported account:   Accounts in this organizational directory only (Single tenant)
  Redirect URI:        (vacío)
```

Anota:
- **Application (client) ID**
- **Directory (tenant) ID**

### 4.2 Generar el client secret

```
Certificates & secrets → Client secrets → New client secret
  Description: cursor-cloud-agent-90d
  Expires:     90 days
  → Copia el VALOR (no el secret ID) inmediatamente; solo se muestra una vez.
```

Recomendación más fuerte: usar **certificado** en lugar de client secret (`Certificates & secrets → Certificates → Upload certificate`). El connector `connect_entra.ps1` soporta ambos. Si vais por certificado, lo más limpio es generarlo offline:

```bash
openssl req -x509 -newkey rsa:4096 -sha256 -days 365 -nodes \
  -keyout uem-sso-automation.key -out uem-sso-automation.cer \
  -subj "/CN=uem-sso-automation"
# subir uem-sso-automation.cer al app registration
# subir el .key (PKCS#8) como secreto del Cloud Agent
```

### 4.3 Pedir consentimiento de admin para los permisos de Graph

```
API permissions → Add a permission → Microsoft Graph → Application permissions
  ✓ Application.ReadWrite.OwnedBy        (limita el blast radius vs ReadWrite.All)
  ✓ Application.ReadWrite.All            (necesario para instanciar gallery app)
  ✓ Directory.ReadWrite.All
  ✓ Synchronization.ReadWrite.All
  ✓ Policy.ReadWrite.ApplicationConfiguration
  → Grant admin consent for live.uem.es
```

> `Application.ReadWrite.OwnedBy` por sí solo NO basta porque la app va a tener que crear/configurar otra Enterprise App distinta a sí misma. Por eso se piden ambas. Si UEM exige reducirlo, se puede mover a flujo "create once with All, then revoke All and keep only OwnedBy" — pero requiere doble pasada manual.

### 4.4 Resumen de permisos finales

| Permiso (Application) | Por qué |
|---|---|
| `Application.ReadWrite.All` | Instanciar la gallery app `Google Cloud / G Suite Connector by Microsoft`. |
| `Directory.ReadWrite.All` | Asignar usuario de prueba al SP. |
| `Synchronization.ReadWrite.All` | Crear el sync job, aplicar schema, leer estado (sin Start). |
| `Policy.ReadWrite.ApplicationConfiguration` | Crear y asociar la claims-mapping policy. |

---

## 5. Subir los secretos al Cloud Agent (Cursor)

Ir a [cursor.com/dashboard](https://cursor.com/dashboard) → *Cloud Agents → Secrets* y añadir, **scoped al repo** `azure-entra-id-migration-universidad-europea`:

| Nombre del secreto | Contenido | Origen |
|---|---|---|
| `LIVE_UEM_ES_GOOGLE_SA_JSON` | Contenido **completo** del fichero JSON de la SA descargado en §3.3. | GCP. |
| `LIVE_UEM_ES_GOOGLE_IMPERSONATE_SUBJECT` | `entra-id-conector@live.uem.es` (o el Super Admin temporal del bootstrap). | Decisión §3.5. |
| `LIVE_UEM_ES_ENTRA_TENANT_ID` | Directory (tenant) ID. | §4.1. |
| `LIVE_UEM_ES_ENTRA_CLIENT_ID` | Application (client) ID. | §4.1. |
| `LIVE_UEM_ES_ENTRA_CLIENT_SECRET` | Valor del client secret. **Vacío si usas certificado.** | §4.2. |
| `LIVE_UEM_ES_ENTRA_CLIENT_CERT_PEM` | PEM del certificado privado (key + cert concatenados). **Vacío si usas client secret.** | §4.2. |

Para los próximos 2 tenants, repetir con prefijo `<TENANT_LABEL_UPPER>_*` (ej. `CEG_*`, `UDI_*`).

> **Nunca** poner estos valores en `config/tenants/*.vars`. El fichero `.vars` solo lleva identificadores no sensibles. Los secretos se inyectan como variables de entorno cuando el Cloud Agent arranca; los scripts del repo (`scripts/common/connect_entra.ps1`, `scripts/common/bootstrap_gam_sa.sh`) los consumen desde `$env`.

---

## 6. Rotación y revocación

- Client secret de Entra: caduca a 90 días. Antes de la caducidad, generar uno nuevo (§4.2), actualizar `*_ENTRA_CLIENT_SECRET` en Cursor, validar con `pwsh -File scripts/common/connect_entra.ps1 -VarsFile ...`, borrar el secret antiguo en Entra.
- JSON de la SA Google: rotar la *key*, no la cuenta (`IAM → Service Accounts → Keys → Add Key → JSON`); actualizar `*_GOOGLE_SA_JSON`; borrar la key antigua.
- Calendario sugerido: rotación cada 90 días, alineada con la caducidad del client secret.

## 7. Revocación de emergencia (kill-switch)

Si se sospecha de compromiso:

1. **Entra**: app registration → *Certificates & secrets* → borrar TODAS las secrets/certs activas. Esto deja la app sin forma de autenticarse en <30 s. (`API permissions → Revoke admin consent` si se quiere endurecer aún más.)
2. **Google**: Admin Console → API controls → Manage Domain Wide Delegation → eliminar la entrada de la SA. La SA queda inerte para Workspace.
3. **GCP**: IAM → Service Accounts → `uem-sso-automation` → *Disable*. Borrar las keys.
4. **Cursor**: Dashboard → Secrets → borrar los 6 secretos del tenant afectado.
5. Notificar a UEM IT y a Lutech ops; abrir incidente; revisar audit logs (Google Admin Reports + Entra Sign-in / Audit logs).

---

## 8. Checklist rápida (por tenant)

- [ ] §2 Aprobaciones escritas obtenidas.
- [ ] §3.1–§3.3 Proyecto GCP, APIs habilitadas, SA creada, JSON descargado y guardado en gestor corporativo.
- [ ] §3.4 Domain-Wide Delegation autorizada con los 6 scopes EXACTOS.
- [ ] §3.5 Subject de impersonación decidido y documentado.
- [ ] §4.1–§4.3 App registration creada, secret/cert generado, admin consent concedido para los 4 permisos Graph.
- [ ] §5 Los 6 secretos cargados en Cursor (Cloud Agents → Secrets), scoped al repo.
- [ ] §6 Recordatorio de rotación a 90 días en el calendario del equipo.
- [ ] §7 El procedimiento de revocación de emergencia está leído y al alcance del on-call.
