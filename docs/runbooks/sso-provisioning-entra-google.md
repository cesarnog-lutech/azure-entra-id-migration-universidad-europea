# Runbook — SSO + Provisioning (Entra ID ↔ Google Workspace)

**Tenant en curso:** `live.uem.es` (Live)
**Referencia:** Acta de Proyecto UEM · Lutech v3 (secciones 7 y 8)
**Autor:** César Nogueira — Lutech Sweeft
**Fecha:** 2026-04-23

> **REGLA DE ORO DE ESTA SESIÓN**
>
> - Crear **Test OU**, **perfil SSO** en Google, **Enterprise Application** en Entra ID y **mappings**.
> - Esperar el **análisis del grupo** antes de activar.
> - **NO habilitar el SSO** todavía.
> - **NO aplicar cambios (Apply)** todavía: dejar el perfil SSO en modo "Off" y el provisioning en estado "Ready to provision" sin iniciar.

---

## 0.0 Automatización disponible

Este runbook está respaldado por scripts que ejecutan las partes *mecánicas* (crear OUs, instanciar la app de galería, aplicar la configuración SAML, cargar mappings, etc.) para reducir errores humanos. Hay tres bloques que **NO son automatizables** y siguen siendo manuales por diseño:

- **Login interactivo con MFA** en Google Admin y en Entra ID (los scripts asumen una sesión ya autenticada: GAM7 para Google, `Connect-MgGraph` para Entra).
- **Diálogo OAuth "Authorize"** del provisioning (hay que elegir la cuenta `Entra ID Conector` en el popup de Google y aceptar los scopes).
- **Los toggles finales**: subir el switch de SSO en Google y pulsar *Start provisioning* en Entra. En la sesión actual esos dos pasos están **prohibidos** y los scripts se niegan a ejecutarlos mientras `FREEZE_*=true` en el fichero de variables.

Ficheros:

| Ruta | Qué hace |
|---|---|
| `config/tenants/<dominio>.vars` | Variables por tenant (fuente única de verdad). |
| `config/tenants/_TEMPLATE.vars` | Plantilla para clonar a los dos tenants siguientes. |
| `scripts/common/validate_vars.py` | Valida el fichero de variables antes de tocar nada. |
| `scripts/common/load_vars.sh` | Carga + valida variables para los scripts bash. |
| `scripts/google/01_create_ous_and_service_user.sh` | §1: OUs `/test SSO`, `/local_login`, `/Sync users` + usuario `Entra ID Conector`. |
| `scripts/google/02_create_sso_profile.sh` | §2: perfil SSO `Entra ID` sin asignar, toggle OFF. |
| `scripts/entra/01_create_enterprise_app.ps1` | §3.1: instancia `Google Cloud / G Suite Connector by Microsoft` desde la galería. |
| `scripts/entra/02_configure_saml.ps1` | §3.2: SAML Basic, claims y descarga del certificado Base64. |
| `scripts/entra/03_configure_provisioning.ps1` | §4: provisioning Automatic, mappings con `orgUnitPath`=Constant `/test SSO`, grupos OFF, **sin arrancar el job**. |

Flujo recomendado para `live.uem.es`:

```bash
python3 scripts/common/validate_vars.py config/tenants/live.uem.es.vars

DRY_RUN=1 bash scripts/google/01_create_ous_and_service_user.sh config/tenants/live.uem.es.vars
DRY_RUN=0 bash scripts/google/01_create_ous_and_service_user.sh config/tenants/live.uem.es.vars

DRY_RUN=1 bash scripts/google/02_create_sso_profile.sh config/tenants/live.uem.es.vars
DRY_RUN=0 bash scripts/google/02_create_sso_profile.sh config/tenants/live.uem.es.vars

pwsh -File scripts/entra/01_create_enterprise_app.ps1 \
  -VarsFile config/tenants/live.uem.es.vars -WhatIf
pwsh -File scripts/entra/01_create_enterprise_app.ps1 \
  -VarsFile config/tenants/live.uem.es.vars

pwsh -File scripts/entra/02_configure_saml.ps1 \
  -VarsFile config/tenants/live.uem.es.vars \
  -AppObjectId $env:ENTRA_APP_OBJECT_ID \
  -ServicePrincipalId $env:ENTRA_SP_OBJECT_ID \
  -AcsUrlFromGoogle '<ACS-URL-que-muestra-Google>' -WhatIf

pwsh -File scripts/entra/03_configure_provisioning.ps1 \
  -VarsFile config/tenants/live.uem.es.vars \
  -ServicePrincipalId $env:ENTRA_SP_OBJECT_ID -WhatIf
```

Todos los scripts son idempotentes y soportan `DRY_RUN=1` / `-WhatIf`.

---

## 0. Pre-requisitos (verificar antes de tocar consolas)

- [ ] Acceso **Super Admin** a Google Admin Console del tenant `live.uem.es`.
- [ ] Acceso **Global Admin** al tenant de Microsoft Entra ID correspondiente a `live.uem.es`.
- [ ] Licencias disponibles: **Microsoft Entra P1+** y **Google Cloud Identity Premium / Workspace** con provisioning habilitado.
- [ ] Dominio `live.uem.es` **verificado como primario** en Google Workspace (equivalente a lo comprobado para `universidadeuropea.es` en la S1 del Acta §7.1).
- [ ] Navegador en modo incógnito / perfil aparte para separar sesiones de Google y Microsoft.
- [ ] URL del PWM corporativo a mano (se usa como Change password URL en ambos lados — ver §7.2 y §7.3 del Acta).

---

## 1. Google Admin Console — Test Organization (OU)

> Objetivo: crear la OU `/test SSO` **idéntica** a la del Acta para poder acotar el alcance y evitar que se rompan usuarios reales.

- [ ] **Login** en [admin.google.com](https://admin.google.com) con la cuenta Super Admin del tenant `live.uem.es`.
- [ ] Ir a **Directory → Organizational units**.
- [ ] Crear OU hija de la raíz con **nombre exacto**: `test SSO` (path resultante: `/test SSO`).
  - Description sugerida: `Ámbito acotado de pruebas SSO/Provisioning Entra ID — Lutech`.
- [ ] Crear además la sub-OU `local_login` (raíz → `local_login`) para cuentas locales/servicio y la OU `Sync users` para alojar la cuenta de servicio del conector (réplica del Acta §7.3 y §8.1).
- [ ] Crear usuario de servicio `Entra ID Conector` dentro de `/Sync users`, asignarle rol **Super Admin**. Guardar contraseña en el gestor corporativo.
- [ ] Verificar que la OU `/test SSO` aparece vacía y que el mecanismo de autenticación por defecto de la sub-OU `local_login` sigue siendo **Google password** (sin SSO).

---

## 2. Google Admin — Perfil SSO de terceros (sin asignar todavía)

Ruta: **Security → Authentication → SSO with third-party IdPs**.

- [ ] **Add SSO profile** → `Third-party SSO profile`.
- [ ] Rellenar los siguientes campos **(idénticos en nombre al Acta §7.3, Tabla de valores)**:

| Campo | Valor a introducir |
|---|---|
| Name of profile | `Entra ID` |
| IDP entity ID | *(pendiente — se obtiene de Azure tras crear la app, paso 3)* |
| Sign-in page URL | *(pendiente — Login URL de Azure)* |
| Sign-out page URL | `https://login.microsoftonline.com/common/wsfederation?wa=wsignout1.0` |
| Change password URL | URL del PWM corporativo de UEM |
| Verification certificate | *(pendiente — certificado Base64 de Azure)* |

- [ ] **NO guardar el perfil con asignación activa todavía.** Dejarlo como borrador o, si la UI de Google obliga a guardar, dejar la asignación **sin asignar a ninguna OU**.
- [ ] Anotar para el paso 3:
  - **ACS URL** que muestra Google en el propio perfil (se usará como *Reply URL* en Entra ID).
  - **Entity ID** de Google: `google.com/a/live.uem.es`.

---

## 3. Microsoft Entra ID — Enterprise Application

> **Mismo nombre que en el otro tenant:** `Google Cloud / G Suite Connector by Microsoft`.

### 3.1 Creación

- [ ] Login en [entra.microsoft.com](https://entra.microsoft.com) con Global Admin del tenant `live.uem.es`.
- [ ] **Applications → Enterprise applications → New application**.
- [ ] Buscar en la galería: `Google Cloud / G Suite Connector by Microsoft`.
- [ ] Crear con el **nombre exacto** (sin renombrar): `Google Cloud / G Suite Connector by Microsoft`.

### 3.2 Single Sign-On (SAML)

Ir a **Single sign-on → SAML**.

- [ ] **Basic SAML Configuration** → Edit. Valores a introducir (réplica del Acta §7.2, solo cambiando el dominio):

| Campo Entra ID | Valor para live.uem.es |
|---|---|
| Identifier (Entity ID) | `google.com/a/live.uem.es` |
| Reply URL (ACS) | ACS URL obtenida del perfil SSO de Google del paso 2 |
| Sign-on URL | `https://www.google.com/a/live.uem.es/ServiceLogin?continue=https://console.cloud.google.com/` |
| Change password URL | URL del PWM corporativo de UEM |

- [ ] **Attributes & Claims** → Edit. Configurar exactamente estos claims (mismos del Acta §7.2, Tabla de claims):

| Claim (SAML) | Valor (Entra ID) | Namespace |
|---|---|---|
| Unique User Identifier (Name ID) | `user.userprincipalname` | (Name ID) |
| givenname | `user.givenname` | http://schemas.xmlsoap.org/ws/2005/05/identity/claims |
| surname | `user.surname` | http://schemas.xmlsoap.org/ws/2005/05/identity/claims |
| emailaddress | `user.mail` | http://schemas.xmlsoap.org/ws/2005/05/identity/claims |
| name | `user.userprincipalname` | http://schemas.xmlsoap.org/ws/2005/05/identity/claims |

- [ ] **SAML Certificates** → **Download** `Certificate (Base64)`. Guardar como `live.uem.es-entraid-saml.cer`.
- [ ] En **Set up Google Cloud / G Suite Connector by Microsoft** anotar:
  - **Login URL** → este valor va al campo *Sign-in page URL* del perfil SSO de Google.
  - **Microsoft Entra Identifier** → este valor va al campo *IDP entity ID* del perfil SSO de Google.

### 3.3 Cerrar el lazo en Google (completar el perfil)

- [ ] Volver al perfil SSO `Entra ID` creado en el paso 2 y rellenar:
  - `IDP entity ID` ← Microsoft Entra Identifier
  - `Sign-in page URL` ← Login URL
  - `Verification certificate` ← subir `live.uem.es-entraid-saml.cer`
- [ ] **Guardar el perfil, pero NO asignarlo a `/test SSO` aún. Dejar el toggle de SSO en OFF.**

---

## 4. Entra ID — Provisioning (Google Cloud / G Suite Connector)

Ir a la aplicación → **Provisioning**.

- [ ] **Provisioning Mode** = `Automatic` (cambiar explícitamente desde `Manual`, como en la S1).
- [ ] **Admin Credentials**:
  - Click **Authorize** → en el diálogo de Google seleccionar la cuenta **`Entra ID Conector`** creada en el paso 1.
  - Conceder consentimiento.
  - Ejecutar **Test Connection**. Debe devolver OK antes de continuar.

### 4.1 Mappings de usuarios (idénticos al Acta §8.3)

En **Mappings → Provision Azure Active Directory Users**, configurar exactamente:

| Google Cloud / Workspace Attribute | Microsoft Entra ID Attribute |
|---|---|
| `userPrincipalName` | `primaryEmail` / `userPrincipalName` |
| `mail` | `emails[type eq "work"].value` |
| `displayName` | `name.formatted` |
| `givenName` | `name.givenName` |
| `surname` | `name.familyName` |
| `orgUnitPath` | **Constant** `/test SSO` |

> El atributo `orgUnitPath` debe ser de tipo **Constant** con valor literal `/test SSO`. Esto fuerza que cualquier usuario sincronizado durante las pruebas caiga en la OU de prueba y no afecte al directorio real.

### 4.2 Mappings de grupos

- [ ] **Provision Azure Active Directory Groups → Disabled**. (Decisión del Acta §8.4: la sincronización de grupos queda deshabilitada para esta fase.)

### 4.3 Settings

- [ ] **Send an email notification when a failure occurs** = ON.
- [ ] **Notification Email** = buzón de operaciones del equipo Lutech + UEM IT (a confirmar con Alejandro Serrano).
- [ ] **Prevent accidental deletion** = ON, con el umbral por defecto.
- [ ] **Scope** = *Sync only assigned users and groups*.

### 4.4 Estado del provisioning

- [ ] Dejar **Provisioning Status = OFF** al terminar. **No iniciar la sincronización.**
- [ ] Asignar al menos **1 usuario de prueba** (en `Users and groups`) pero **sin arrancar el provisioning**. Esto permite que Entra ID realice el **análisis del grupo / scoping** sin escribir aún en Google.

---

## 5. Esperar análisis del grupo

- [ ] Revisar en **Provisioning → Provisioning logs** que no haya errores de scoping previos a la activación.
- [ ] Verificar en el panel **Overview** de provisioning que aparezcan métricas de usuarios analizados (cuenta de *in scope* esperada = 1 o los asignados manualmente).
- [ ] Una vez completado el análisis, **parar aquí**. No pulsar **Start provisioning**, no pulsar **Apply** en el perfil SSO de Google.

---

## 6. Checkpoint final de la sesión (pre-aprobación)

Antes de cerrar la sesión, confirmar visualmente en consolas que:

- [ ] Google Admin → perfil SSO `Entra ID` existe, pero **no está asignado** a ninguna OU. Toggle en **OFF**.
- [ ] Google Admin → OU `/test SSO` existe y está **vacía**.
- [ ] Entra ID → Enterprise Application `Google Cloud / G Suite Connector by Microsoft` existe.
- [ ] Entra ID → SAML config completa (Entity ID, Reply URL, claims, certificado descargado).
- [ ] Entra ID → Provisioning mode = Automatic, Test Connection OK, Mappings configurados, **Provisioning Status = OFF**.
- [ ] `orgUnitPath` = constante `/test SSO` (doble verificación — es la salvaguarda clave).
- [ ] Ningún "Apply" o "Start" pulsado.

> Una vez en este punto, la configuración está **lista para análisis y revisión**. Se activará en la siguiente sesión con aprobación explícita de UEM.

---

## 7. Replicación en los otros 2 tenants (TBD)

Cuando se confirmen los 2 tenants adicionales, clonar esta checklist cambiando solo las variables por tenant. Matriz a rellenar:

| Variable | Tenant A: `live.uem.es` | Tenant B: *(TBD)* | Tenant C: *(TBD)* |
|---|---|---|---|
| Dominio primario | `live.uem.es` |  |  |
| Entity ID (Entra) | `google.com/a/live.uem.es` |  |  |
| Sign-on URL | `https://www.google.com/a/live.uem.es/ServiceLogin?continue=https://console.cloud.google.com/` |  |  |
| Nombre Enterprise App | `Google Cloud / G Suite Connector by Microsoft` | *(mismo)* | *(mismo)* |
| Nombre perfil SSO Google | `Entra ID` | *(mismo)* | *(mismo)* |
| OU de prueba | `/test SSO` | `/test SSO` | `/test SSO` |
| orgUnitPath constante | `/test SSO` | `/test SSO` | `/test SSO` |
| Certificado SAML (archivo) | `live.uem.es-entraid-saml.cer` | *(renombrar al dominio)* | *(renombrar al dominio)* |
| Cuenta de servicio Google | `Entra ID Conector` @ `/Sync users` | *(mismo)* | *(mismo)* |
| Sync de grupos | OFF | OFF | OFF |
| Estado final sesión | SSO Off + Provisioning Off | SSO Off + Provisioning Off | SSO Off + Provisioning Off |

Candidatos probables (según Acta §4 y §6): CEG (`centrogarrigues.com`), UDI, Andorra, Portugal. Confirmar con Jorge Ysart y Alejandro Serrano cuáles serán los 2 siguientes.

---

## 8. Riesgos y notas heredadas del Acta

- **Inaccessible domain** (Acta §8.6): si al asignar un usuario de prueba el dominio de su UPN no coincide con los dominios verificados del tenant Google, el provisioning on-demand falla. Verificar antes que `live.uem.es` esté **verificado como primario** en Google.
- **`admin_policy_enforced` (error 400)**: si aparece durante la autorización del conector, revisar **API Controls → Domain-wide delegation** en Google Admin (Acta §8.2, Figura 10a).
- **Usuarios preexistentes en Google**: al asignar la app en Entra a un usuario que ya existe en Google vía AD on-premise, confirmar que no se rompe (caso de prueba específico del Acta §7.5).
- **MFA**: no tocar MFA en este paso. Se mantiene lo acordado: MFA de Entra ID, deshabilitado en Google en la OU que se federe (solo cuando se active el SSO, no ahora).
