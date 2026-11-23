# =============================================================================
# Config.ps1 - YAML loading and safe accessors
# =============================================================================

Set-StrictMode -Version Latest

# Ensures the powershell-yaml module is available, installing it from the
# PowerShell Gallery if needed. Idempotent.
function Initialize-GlazierYaml {
    if (Get-Module -ListAvailable -Name 'powershell-yaml') {
        Import-Module powershell-yaml -ErrorAction Stop
        return
    }

    Write-GlazierLog -Level Info -Message 'Installing powershell-yaml module (first run only)...'
    try {
        [Net.ServicePointManager]::SecurityProtocol = `
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }

    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
    }
    if ((Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue).InstallationPolicy -ne 'Trusted') {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
    }
    Install-Module -Name powershell-yaml -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    Import-Module powershell-yaml -ErrorAction Stop
}

function Import-GlazierConfig {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Config file not found: $Path"
    }
    Initialize-GlazierYaml
    $raw = Get-Content -LiteralPath $Path -Raw
    $config = ConvertFrom-Yaml $raw
    if ($null -eq $config) {
        throw "Config file is empty or invalid: $Path"
    }
    return $config
}

# Reads a dotted key path (e.g. 'applications.nvidiaApp.mode') from a hashtable
# tree, returning $Default when any segment is missing. Keeps modules tidy and
# tolerant of partially-specified configs.
function Get-GlazierValue {
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$Key,
        $Default = $null
    )
    $node = $Config
    foreach ($segment in $Key.Split('.')) {
        if ($null -eq $node) { return $Default }
        if ($node -is [System.Collections.IDictionary]) {
            if (-not $node.Contains($segment)) { return $Default }
            $node = $node[$segment]
        } else {
            return $Default
        }
    }
    if ($null -eq $node) { return $Default }
    return $node
}

# Convenience: is a feature section enabled? A section is "on" when it exists and
# its `enabled` key is not explicitly false.
function Test-GlazierEnabled {
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$Key
    )
    $section = Get-GlazierValue -Config $Config -Key $Key
    if ($null -eq $section) { return $false }
    if ($section -is [System.Collections.IDictionary] -and $section.Contains('Enabled')) {
        return [bool]$section['Enabled']
    }
    return $true
}
