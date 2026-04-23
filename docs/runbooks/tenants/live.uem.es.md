# Tenant tracker — `live.uem.es`

**Estado de la sesión:** preparación (configuración cargada, **sin activar**).
**Runbook de referencia:** [`../sso-provisioning-entra-google.md`](../sso-provisioning-entra-google.md)
**Última actualización:** 2026-04-23

> Esta hoja es el "estado vivo" del tenant. Se actualiza tras cada sesión.
> La regla de oro de la sesión actual sigue vigente: **NO habilitar SSO**, **NO pulsar Apply / Start provisioning**.

---

## Variables del tenant

| Variable | Valor |
|---|---|
| Dominio primario | `live.uem.es` |
| Entity ID (Entra → Google) | `google.com/a/live.uem.es` |
| Sign-on URL | `https://www.google.com/a/live.uem.es/ServiceLogin?continue=https://console.cloud.google.com/` |
| Sign-out URL (Google) | `https://login.microsoftonline.com/common/wsfederation?wa=wsignout1.0` |
| Nombre Enterprise App (Entra) | `Google Cloud / G Suite Connector by Microsoft` |
| Nombre perfil SSO (Google) | `Entra ID` |
| OU de prueba | `/test SSO` |
| OU de cuentas locales | `/local_login` |
| OU de cuenta de servicio | `/Sync users` |
| Cuenta de servicio Google | `Entra ID Conector` (Super Admin, en `/Sync users`) |
| `orgUnitPath` (constante) | `/test SSO` |
| Sync de grupos | OFF |
| Certificado SAML (archivo) | `live.uem.es-entraid-saml.cer` |
| Change password URL | *(URL del PWM corporativo de UEM — pendiente de pegar)* |
| Notification email | *(buzón ops Lutech + UEM IT — pendiente de confirmar con Alejandro Serrano)* |

---

## Valores que se obtienen *runtime* de Azure (rellenar tras el paso 3.2)

| Campo | Valor obtenido |
|---|---|
| Login URL (Azure) → *Sign-in page URL* en Google | `…` |
| Microsoft Entra Identifier → *IDP entity ID* en Google | `…` |
| Logout URL (Azure) | `…` |
| Thumbprint del certificado | `…` |
| Vencimiento del certificado | `YYYY-MM-DD` |

## Valores que se obtienen *runtime* de Google (rellenar tras el paso 2)

| Campo | Valor obtenido |
|---|---|
| ACS URL (Google) → *Reply URL* en Entra | `…` |
| Entity ID (Google) | `google.com/a/live.uem.es` |

---

## Checklist de avance (espejo del runbook)

- [ ] §0 Pre-requisitos verificados.
- [ ] §1 OU `/test SSO`, `/local_login`, `/Sync users` creadas; usuario `Entra ID Conector` con Super Admin.
- [ ] §2 Perfil SSO `Entra ID` creado en Google **sin asignación** y con toggle OFF.
- [ ] §3.1 Enterprise App creada en Entra con el nombre exacto.
- [ ] §3.2 SAML Basic config + claims + certificado descargado.
- [ ] §3.3 Perfil SSO de Google completado con datos de Azure (sin asignar OU).
- [ ] §4 Provisioning Automatic + Authorize OK + Test Connection OK.
- [ ] §4.1 Mappings de usuarios cargados; `orgUnitPath` = constante `/test SSO` (verificado dos veces).
- [ ] §4.2 Mappings de grupos = Disabled.
- [ ] §4.3 Settings: notificación, prevent accidental deletion, scope = assigned.
- [ ] §4.4 1 usuario de prueba asignado; **Provisioning Status = OFF**.
- [ ] §5 Análisis del grupo completado sin errores en logs.
- [ ] §6 Checkpoint final visual confirmado.

## Bloqueos / pendientes

- [ ] Confirmar URL del PWM corporativo (Change password URL) con UEM IT.
- [ ] Confirmar buzón de notificaciones con Alejandro Serrano.
- [ ] Confirmar que `live.uem.es` está verificado como **dominio primario** en Google Workspace.

## Decisiones tomadas en esta sesión

- Sync de grupos: **OFF** (Acta §8.4).
- Scope de provisioning: **assigned users and groups** únicamente.
- `orgUnitPath` forzado por **Constant** = `/test SSO` para acotar el blast radius.

## Riesgos vivos

- Inaccessible domain si UPN no coincide con dominios verificados (Acta §8.6).
- `admin_policy_enforced` durante Authorize → revisar Domain-wide delegation (Acta §8.2).
- Usuarios preexistentes vía AD on-prem (Acta §7.5).
- MFA: no se toca aún. Cuando se active el SSO, deshabilitar MFA de Google en la OU federada y mantener MFA de Entra.
