<#
.SYNOPSIS
    Paso 4 del runbook. Configura la sincronizacion (provisioning) de la
    Enterprise App del conector de Google, SIN iniciar la sincronizacion.

.DESCRIPTION
    - Crea el job de sincronizacion si no existe (template 'gsuite').
    - Aplica el mapping de usuarios tal como marca el Acta §8.3, con
      orgUnitPath = constante "/test SSO".
    - Deshabilita el mapping de grupos.
    - Configura:
        * notification email on failure = ON
        * prevent accidental deletion   = ON (umbral por defecto)
        * scope = "Sync only assigned users and groups"
    - NO ejecuta Start-MgServicePrincipalSynchronizationJob mientras
      FREEZE_ENTRA_PROVISIONING_START=true (fail-closed).

.PARAMETER VarsFile
.PARAMETER ServicePrincipalId

.EXAMPLE
    pwsh -File scripts/entra/03_configure_provisioning.ps1 `
      -VarsFile config/tenants/live.uem.es.vars `
      -ServicePrincipalId $env:ENTRA_SP_OBJECT_ID `
      -WhatIf
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string] $VarsFile,
    [Parameter(Mandatory = $true)][string] $ServicePrincipalId
)

$ErrorActionPreference = 'Stop'

function Read-Vars {
    param([string] $Path)
    $vars = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trim = $line.Trim()
        if ($trim -eq '' -or $trim.StartsWith('#')) { continue }
        if ($trim -match '^\s*([A-Z_][A-Z0-9_]*)\s*=\s*"?([^"]*)"?\s*$') {
            $name = $Matches[1]; $val = $Matches[2]
            $val = [regex]::Replace($val, '\$\{([A-Z_][A-Z0-9_]*)\}', { param($m) $vars[$m.Groups[1].Value] })
            $vars[$name] = $val
        }
    }
    return $vars
}

$vars = Read-Vars -Path $VarsFile
$required = @('ORG_UNIT_PATH_CONSTANT','PROVISIONING_NOTIFICATION_EMAIL','FREEZE_ENTRA_PROVISIONING_START')
foreach ($r in $required) {
    if (-not $vars.ContainsKey($r) -or [string]::IsNullOrWhiteSpace($vars[$r])) {
        throw "Variable obligatoria vacia: $r"
    }
}

if ($vars.ORG_UNIT_PATH_CONSTANT -ne '/test SSO') {
    throw "orgUnitPath constante debe ser EXACTAMENTE '/test SSO' en esta fase. Valor recibido: '$($vars.ORG_UNIT_PATH_CONSTANT)'"
}

if (-not (Get-MgContext)) {
    throw "No hay sesion activa de Microsoft Graph. Conectate primero con los scopes: 'Application.ReadWrite.All','Synchronization.ReadWrite.All','Directory.ReadWrite.All'"
}

Write-Host "== Paso 4: Provisioning (Automatic) =="
Write-Host "   SP objectId         : $ServicePrincipalId"
Write-Host "   orgUnitPath constant: $($vars.ORG_UNIT_PATH_CONSTANT)"
Write-Host "   freeze Start        : $($vars.FREEZE_ENTRA_PROVISIONING_START)"
Write-Host ""

$job = Get-MgServicePrincipalSynchronizationJob -ServicePrincipalId $ServicePrincipalId -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $job) {
    if ($PSCmdlet.ShouldProcess($ServicePrincipalId, "Create synchronization job (template: gsuite)")) {
        $job = New-MgServicePrincipalSynchronizationJob -ServicePrincipalId $ServicePrincipalId -TemplateId 'gsuite'
        Write-Host "[ok] job creado: $($job.Id)"
    }
    else {
        Write-Host "[WhatIf] se habria creado el job de sincronizacion con template 'gsuite'"
        return
    }
}
else {
    Write-Host "[skip] ya existe job de sincronizacion: $($job.Id)"
}

$schemaJson = @'
{
  "synchronizationRules": [
    {
      "name": "USER_OUTBOUND_LIVE_UEM",
      "sourceDirectoryName": "Azure Active Directory",
      "targetDirectoryName": "Google Workspace",
      "objectMappings": [
        {
          "sourceObjectName": "User",
          "targetObjectName": "User",
          "enabled": true,
          "scope": { "filterGroups": [] },
          "attributeMappings": [
            { "source": { "name":"userPrincipalName","type":"Attribute" }, "targetAttributeName":"primaryEmail" },
            { "source": { "name":"userPrincipalName","type":"Attribute" }, "targetAttributeName":"userPrincipalName" },
            { "source": { "name":"mail","type":"Attribute" }, "targetAttributeName":"emails[type eq \"work\"].value" },
            { "source": { "name":"displayName","type":"Attribute" }, "targetAttributeName":"name.formatted" },
            { "source": { "name":"givenName","type":"Attribute" }, "targetAttributeName":"name.givenName" },
            { "source": { "name":"surname","type":"Attribute" }, "targetAttributeName":"name.familyName" },
            { "source": { "expression":"\"/test SSO\"","type":"Constant" }, "targetAttributeName":"orgUnitPath" }
          ]
        },
        { "sourceObjectName": "Group", "targetObjectName": "Group", "enabled": false, "attributeMappings": [] }
      ]
    }
  ]
}
'@

if ($PSCmdlet.ShouldProcess($job.Id, "Apply synchronization schema (user mappings + groups disabled)")) {
    $tmp = New-TemporaryFile
    Set-Content -LiteralPath $tmp -Value $schemaJson -Encoding utf8
    Invoke-MgGraphRequest -Method PUT `
        -Uri "/v1.0/servicePrincipals/$ServicePrincipalId/synchronization/jobs/$($job.Id)/schema" `
        -InputFilePath $tmp | Out-Null
    Remove-Item $tmp -Force
    Write-Host "[ok] schema aplicada (orgUnitPath=Constant '/test SSO', Groups=disabled)"
}

$secretsBody = @{
    value = @(
        @{ key = 'NotificationEmail'; value = $vars.PROVISIONING_NOTIFICATION_EMAIL }
        @{ key = 'SyncNotificationSettings'; value = '{"Enabled":true,"DeleteThresholdEnabled":true}' }
        @{ key = 'SyncAll'; value = 'false' }
    )
}

if ($PSCmdlet.ShouldProcess($ServicePrincipalId, "Set synchronization secrets (notifications, scope=assigned)")) {
    Invoke-MgGraphRequest -Method PUT `
        -Uri "/v1.0/servicePrincipals/$ServicePrincipalId/synchronization/secrets" `
        -Body ($secretsBody | ConvertTo-Json -Depth 5) -ContentType 'application/json' | Out-Null
    Write-Host "[ok] secrets aplicados (notificaciones=ON, scope=assigned)"
}

Write-Host ""
if ($vars.FREEZE_ENTRA_PROVISIONING_START -eq 'true') {
    Write-Host "== Provisioning Status = OFF =="
    Write-Host "   FREEZE_ENTRA_PROVISIONING_START=true. NO se llama Start-MgServicePrincipalSynchronizationJob."
    Write-Host "   Asigna 1 usuario de prueba manualmente y deja que Entra ejecute el analisis del grupo."
}
else {
    Write-Warning "FREEZE_ENTRA_PROVISIONING_START=false. Este script NO arranca el job; hazlo explicitamente en la sesion de activacion."
}
