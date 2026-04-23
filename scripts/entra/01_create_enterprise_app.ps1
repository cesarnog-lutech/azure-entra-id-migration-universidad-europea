<#
.SYNOPSIS
    Paso 3.1 del runbook. Crea la Enterprise Application
    "Google Cloud / G Suite Connector by Microsoft" desde la galeria,
    con el nombre exacto, en el tenant live.uem.es.

.DESCRIPTION
    Idempotente: si la aplicacion ya existe con ese displayName, no la
    duplica. Devuelve por stdout los IDs necesarios para los siguientes
    pasos (applicationId, servicePrincipalId, objectId).

    Respeta -WhatIf para ejecutar en modo dry-run.

.PARAMETER VarsFile
    Ruta al fichero de variables del tenant (config/tenants/<dominio>.vars).

.EXAMPLE
    pwsh -File scripts/entra/01_create_enterprise_app.ps1 -VarsFile config/tenants/live.uem.es.vars -WhatIf
    pwsh -File scripts/entra/01_create_enterprise_app.ps1 -VarsFile config/tenants/live.uem.es.vars

.NOTES
    Requiere modulo Microsoft.Graph (Install-Module Microsoft.Graph -Scope CurrentUser)
    y conexion previa con: Connect-MgGraph -TenantId <ENTRA_TENANT_ID> -Scopes "Application.ReadWrite.All","Directory.ReadWrite.All"
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string] $VarsFile
)

$ErrorActionPreference = 'Stop'

function Read-Vars {
    param([string] $Path)
    if (-not (Test-Path $Path)) { throw "Vars file no encontrado: $Path" }
    $vars = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trim = $line.Trim()
        if ($trim -eq '' -or $trim.StartsWith('#')) { continue }
        if ($trim -match '^\s*([A-Z_][A-Z0-9_]*)\s*=\s*"?([^"]*)"?\s*$') {
            $name = $Matches[1]
            $val  = $Matches[2]
            $val  = [regex]::Replace($val, '\$\{([A-Z_][A-Z0-9_]*)\}', { param($m) $vars[$m.Groups[1].Value] })
            $vars[$name] = $val
        }
    }
    return $vars
}

$vars = Read-Vars -Path $VarsFile
$required = @('TENANT_PRIMARY_DOMAIN','ENTRA_APP_DISPLAY_NAME')
foreach ($r in $required) {
    if (-not $vars.ContainsKey($r) -or [string]::IsNullOrWhiteSpace($vars[$r])) {
        throw "Variable obligatoria vacia: $r"
    }
}

Write-Host "== Paso 3.1: Enterprise Application =="
Write-Host "   tenant : $($vars.TENANT_PRIMARY_DOMAIN)"
Write-Host "   display: $($vars.ENTRA_APP_DISPLAY_NAME)"
Write-Host ""

if (-not (Get-MgContext)) {
    throw "No hay sesion activa de Microsoft Graph. Ejecuta primero: Connect-MgGraph -TenantId <...> -Scopes 'Application.ReadWrite.All','Directory.ReadWrite.All'"
}

$existing = Get-MgServicePrincipal -Filter "displayName eq '$($vars.ENTRA_APP_DISPLAY_NAME)'" -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "[skip] Ya existe un service principal con ese displayName:"
    Write-Host "       appId=$($existing.AppId) spId=$($existing.Id)"
    return
}

$templateId = $vars.ENTRA_APP_TEMPLATE_ID
if ([string]::IsNullOrWhiteSpace($templateId)) {
    Write-Host "[resolve] buscando applicationTemplateId en la galeria..."
    $template = Get-MgApplicationTemplate -Filter "displayName eq '$($vars.ENTRA_APP_DISPLAY_NAME)'" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $template) {
        throw "No se pudo resolver applicationTemplateId desde la galeria. Rellena ENTRA_APP_TEMPLATE_ID en el vars file."
    }
    $templateId = $template.Id
    Write-Host "[resolve] templateId=$templateId"
}

if ($PSCmdlet.ShouldProcess($vars.ENTRA_APP_DISPLAY_NAME, "Instantiate gallery app")) {
    $instance = Invoke-MgInstantiateApplicationTemplate -ApplicationTemplateId $templateId -DisplayName $vars.ENTRA_APP_DISPLAY_NAME
    Write-Host ""
    Write-Host "== Creada =="
    Write-Host "   appId              : $($instance.Application.AppId)"
    Write-Host "   appObjectId        : $($instance.Application.Id)"
    Write-Host "   servicePrincipalId : $($instance.ServicePrincipal.Id)"
    Write-Host ""
    Write-Host "Exporta estos IDs para el siguiente paso:"
    Write-Host "   `$env:ENTRA_APP_ID='$($instance.Application.AppId)'"
    Write-Host "   `$env:ENTRA_APP_OBJECT_ID='$($instance.Application.Id)'"
    Write-Host "   `$env:ENTRA_SP_OBJECT_ID='$($instance.ServicePrincipal.Id)'"
}
else {
    Write-Host "[WhatIf] se habria instanciado la gallery app '$($vars.ENTRA_APP_DISPLAY_NAME)' con templateId=$templateId"
}
