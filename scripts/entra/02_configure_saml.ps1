<#
.SYNOPSIS
    Paso 3.2 del runbook. Configura SAML (Basic config + Claims) para la
    Enterprise App "Google Cloud / G Suite Connector by Microsoft" y
    descarga el certificado Base64.

.DESCRIPTION
    - Basic SAML Config: Identifier (Entity ID), Reply URL (ACS), Sign-on URL,
      Logout URL, Change password URL.
    - Claims: Name ID = user.userprincipalname; givenname/surname/emailaddress/name.
    - Descarga del certificado Base64 a SAML_CERT_FILENAME del vars file.

    NO asigna usuarios, NO habilita SSO. Respeta -WhatIf.

.PARAMETER VarsFile
.PARAMETER AppObjectId
    Object ID de la Application (no del service principal).
.PARAMETER ServicePrincipalId
.PARAMETER AcsUrlFromGoogle
    La ACS URL que muestra el perfil SSO de Google tras crearlo (paso 2).

.EXAMPLE
    pwsh -File scripts/entra/02_configure_saml.ps1 `
      -VarsFile config/tenants/live.uem.es.vars `
      -AppObjectId $env:ENTRA_APP_OBJECT_ID `
      -ServicePrincipalId $env:ENTRA_SP_OBJECT_ID `
      -AcsUrlFromGoogle 'https://www.google.com/a/live.uem.es/acs' `
      -WhatIf
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string] $VarsFile,
    [Parameter(Mandatory = $true)][string] $AppObjectId,
    [Parameter(Mandatory = $true)][string] $ServicePrincipalId,
    [Parameter(Mandatory = $true)][string] $AcsUrlFromGoogle
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
$required = @('GOOGLE_ENTITY_ID','GOOGLE_SIGN_ON_URL','GOOGLE_SIGN_OUT_URL','PWM_CHANGE_PASSWORD_URL','SAML_CERT_FILENAME')
foreach ($r in $required) {
    if (-not $vars.ContainsKey($r) -or [string]::IsNullOrWhiteSpace($vars[$r])) {
        throw "Variable obligatoria vacia: $r (rellenala en $VarsFile antes de correr este paso)"
    }
}

if (-not (Get-MgContext)) {
    throw "No hay sesion activa de Microsoft Graph. Ejecuta: Connect-MgGraph -TenantId <...> -Scopes 'Application.ReadWrite.All','Directory.ReadWrite.All','Policy.ReadWrite.ApplicationConfiguration'"
}

Write-Host "== Paso 3.2: SAML Basic + Claims + Certificado =="
Write-Host "   Entity ID : $($vars.GOOGLE_ENTITY_ID)"
Write-Host "   ACS       : $AcsUrlFromGoogle"
Write-Host "   Sign-on   : $($vars.GOOGLE_SIGN_ON_URL)"
Write-Host ""

$webParams = @{
    RedirectUris = @($AcsUrlFromGoogle)
    LogoutUrl    = $vars.GOOGLE_SIGN_OUT_URL
}
$appPatch = @{
    IdentifierUris = @($vars.GOOGLE_ENTITY_ID)
    Web            = $webParams
}
$spPatch = @{
    PreferredSingleSignOnMode = 'saml'
    LoginUrl                  = $vars.GOOGLE_SIGN_ON_URL
    NotificationEmailAddresses = @()
}

if ($PSCmdlet.ShouldProcess($AppObjectId, "Update Application SAML basic config")) {
    Update-MgApplication -ApplicationId $AppObjectId -BodyParameter $appPatch
}
if ($PSCmdlet.ShouldProcess($ServicePrincipalId, "Update ServicePrincipal SSO mode")) {
    Update-MgServicePrincipal -ServicePrincipalId $ServicePrincipalId -BodyParameter $spPatch
}

$claimsPolicyBody = @{
    definition = @(@'
{
  "ClaimsMappingPolicy": {
    "Version": 1,
    "IncludeBasicClaimSet": "true",
    "ClaimsSchema": [
      {"Source":"user","ID":"userprincipalname","SamlClaimType":"http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier"},
      {"Source":"user","ID":"givenname","SamlClaimType":"http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname"},
      {"Source":"user","ID":"surname","SamlClaimType":"http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname"},
      {"Source":"user","ID":"mail","SamlClaimType":"http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress"},
      {"Source":"user","ID":"userprincipalname","SamlClaimType":"http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name"}
    ]
  }
}
'@)
    displayName     = "SAML claims for Google Connector - $($vars.TENANT_PRIMARY_DOMAIN)"
    isOrganizationDefault = $false
}

if ($PSCmdlet.ShouldProcess($ServicePrincipalId, "Create & attach claims mapping policy")) {
    $policy = New-MgPolicyClaimsMappingPolicy -BodyParameter $claimsPolicyBody
    $ref = @{ "@odata.id" = "https://graph.microsoft.com/v1.0/policies/claimsMappingPolicies/$($policy.Id)" }
    New-MgServicePrincipalClaimsMappingPolicyByRef -ServicePrincipalId $ServicePrincipalId -BodyParameter $ref
    Write-Host "[ok] claims mapping policy $($policy.Id) asociada al SP $ServicePrincipalId"
}

if ($PSCmdlet.ShouldProcess($ServicePrincipalId, "Mint and export SAML signing certificate")) {
    $addKey = Add-MgServicePrincipalTokenSigningCertificate -ServicePrincipalId $ServicePrincipalId -DisplayName "CN=$($vars.TENANT_PRIMARY_DOMAIN)"
    if ($addKey -and $addKey.Key) {
        $certBytes = [Convert]::FromBase64String($addKey.Key)
        $b64 = [Convert]::ToBase64String($certBytes, [Base64FormattingOptions]::InsertLineBreaks)
        $pem = "-----BEGIN CERTIFICATE-----`n$b64`n-----END CERTIFICATE-----`n"
        $certPath = Join-Path -Path (Get-Location) -ChildPath $vars.SAML_CERT_FILENAME
        $pem | Out-File -FilePath $certPath -Encoding ascii
        Write-Host "[ok] certificado exportado a $certPath"
    }
    else {
        Write-Warning "No se pudo exportar el certificado en formato Base64; descargalo manualmente desde el portal."
    }
}

Write-Host ""
Write-Host "== Checkpoint =="
Write-Host "   - En el portal, seccion 'Set up ...', copia:"
Write-Host "       * Login URL                 -> iria a AZURE_LOGIN_URL"
Write-Host "       * Microsoft Entra Identifier-> iria a AZURE_IDP_ENTITY_ID"
Write-Host "   - Pega esos valores en el perfil SSO 'Entra ID' de Google (paso 3.3)."
Write-Host "   - El certificado Base64 esta en: $($vars.SAML_CERT_FILENAME)"
