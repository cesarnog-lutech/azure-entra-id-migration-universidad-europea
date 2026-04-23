<#
.SYNOPSIS
    Conexion no-interactiva a Microsoft Graph para el tenant indicado, usando
    los secretos del Cloud Agent (client secret o certificado).

.DESCRIPTION
    Lee de variables de entorno (inyectadas por Cursor desde "Cloud Agents -> Secrets"):
      <PREFIX>_ENTRA_TENANT_ID
      <PREFIX>_ENTRA_CLIENT_ID
      <PREFIX>_ENTRA_CLIENT_SECRET   (opcional)
      <PREFIX>_ENTRA_CLIENT_CERT_PEM (opcional, alternativa al secret)

    Donde <PREFIX> deriva de TENANT_LABEL del vars file (kebab -> SNAKE_CASE).
    Ejemplo: TENANT_LABEL="live-uem-es" -> prefix "LIVE_UEM_ES".

    Falla cerrado si:
      - ENTRA_TENANT_ID del vars file no coincide con el del secreto.
      - No hay ni secret ni cert.

.PARAMETER VarsFile
    Ruta al fichero config/tenants/<dominio>.vars.

.EXAMPLE
    pwsh -File scripts/common/connect_entra.ps1 -VarsFile config/tenants/live.uem.es.vars
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $VarsFile
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
foreach ($r in @('TENANT_LABEL','ENTRA_TENANT_ID')) {
    if (-not $vars.ContainsKey($r) -or [string]::IsNullOrWhiteSpace($vars[$r])) {
        throw "Variable obligatoria vacia en $VarsFile : $r"
    }
}

$prefix = ($vars.TENANT_LABEL -replace '-', '_').ToUpperInvariant()
$envTenantId  = [Environment]::GetEnvironmentVariable("${prefix}_ENTRA_TENANT_ID")
$envClientId  = [Environment]::GetEnvironmentVariable("${prefix}_ENTRA_CLIENT_ID")
$envSecret    = [Environment]::GetEnvironmentVariable("${prefix}_ENTRA_CLIENT_SECRET")
$envCertPem   = [Environment]::GetEnvironmentVariable("${prefix}_ENTRA_CLIENT_CERT_PEM")

foreach ($pair in @(
    @{ Name = "${prefix}_ENTRA_TENANT_ID"; Value = $envTenantId },
    @{ Name = "${prefix}_ENTRA_CLIENT_ID"; Value = $envClientId }
)) {
    if ([string]::IsNullOrWhiteSpace($pair.Value)) {
        throw "Falta secreto: $($pair.Name). Cargalo en Cursor Dashboard -> Cloud Agents -> Secrets."
    }
}

if ($envTenantId -ne $vars.ENTRA_TENANT_ID) {
    throw "Discrepancia: ${prefix}_ENTRA_TENANT_ID='$envTenantId' no coincide con vars.ENTRA_TENANT_ID='$($vars.ENTRA_TENANT_ID)'."
}

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    throw "Modulo Microsoft.Graph no instalado. Ejecuta: Install-Module Microsoft.Graph -Scope CurrentUser -Force"
}

Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

if ($envCertPem) {
    Write-Host "[connect-entra] usando certificado (recomendado)"
    $tmp = New-TemporaryFile
    Set-Content -LiteralPath $tmp -Value $envCertPem -Encoding ascii
    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
    $cert.Import($tmp.FullName)
    Remove-Item $tmp -Force
    Connect-MgGraph -TenantId $envTenantId -ClientId $envClientId -Certificate $cert -NoWelcome | Out-Null
}
elseif ($envSecret) {
    Write-Host "[connect-entra] usando client secret"
    $secure = ConvertTo-SecureString $envSecret -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential($envClientId, $secure)
    Connect-MgGraph -TenantId $envTenantId -ClientSecretCredential $cred -NoWelcome | Out-Null
}
else {
    throw "Falta secreto: define ${prefix}_ENTRA_CLIENT_SECRET o ${prefix}_ENTRA_CLIENT_CERT_PEM."
}

$ctx = Get-MgContext
if (-not $ctx) { throw "Connect-MgGraph no establecio contexto." }
Write-Host "[connect-entra] OK: tenant=$($ctx.TenantId) clientId=$($ctx.ClientId) authType=$($ctx.AuthType) scopes=$($ctx.Scopes -join ',')"
