# =============================================================================
# Common.ps1 - shared helpers for Glazier modules
# =============================================================================
# Dot-sourced by Install.ps1. Provides logging, idempotent registry/state
# helpers, elevation checks and small utilities. Everything here is written to
# be safe under -DryRun (nothing is mutated when $script:GlazierDryRun is true).
# =============================================================================

Set-StrictMode -Version Latest

# --- Run-wide state -----------------------------------------------------------
# These are initialised by Install.ps1 but default sensibly if dot-sourced alone.
if (-not (Get-Variable -Name GlazierDryRun -Scope Script -ErrorAction SilentlyContinue)) {
    $script:GlazierDryRun = $false
}
$script:GlazierChangeCount = 0

# --- Logging ------------------------------------------------------------------
function Write-GlazierLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Info', 'Step', 'Change', 'Skip', 'Warn', 'Error', 'Success')]
        [string]$Level = 'Info'
    )

    $prefixes = @{
        Info    = '  '
        Step    = '==>'
        Change  = ' + '
        Skip    = ' . '
        Warn    = ' ! '
        Error   = ' x '
        Success = ' * '
    }
    $colors = @{
        Info    = 'Gray'
        Step    = 'Cyan'
        Change  = 'Green'
        Skip    = 'DarkGray'
        Warn    = 'Yellow'
        Error   = 'Red'
        Success = 'Green'
    }

    $prefix = $prefixes[$Level]
    $tag = if ($script:GlazierDryRun -and $Level -eq 'Change') { '[dry-run] ' } else { '' }
    Write-Host ("{0} {1}{2}" -f $prefix, $tag, $Message) -ForegroundColor $colors[$Level]
}

function Write-GlazierSection {
    param([Parameter(Mandatory)][string]$Title)
    Write-Host ''
    Write-Host ("=== {0} " -f $Title).PadRight(72, '=') -ForegroundColor White
}

# --- Elevation ----------------------------------------------------------------
function Test-GlazierAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# --- Registry helpers ---------------------------------------------------------
# Idempotent: only writes when the current value differs, logs Change vs Skip,
# honours -DryRun, and creates the key path if missing.
function Set-GlazierRegistryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [ValidateSet('String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'QWord')]
        [string]$Type = 'DWord',
        [string]$Description
    )

    $label = if ($Description) { $Description } else { "$Path\$Name" }

    $current = $null
    $exists = $false
    if (Test-Path -LiteralPath $Path) {
        $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
        if ($null -ne $item -and ($item.PSObject.Properties.Name -contains $Name)) {
            $current = $item.$Name
            $exists = $true
        }
    }

    if ($exists -and ("$current" -eq "$Value")) {
        Write-GlazierLog -Level Skip -Message "$label already = $Value"
        return
    }

    if ($script:GlazierDryRun) {
        Write-GlazierLog -Level Change -Message "$label -> $Value"
        $script:GlazierChangeCount++
        return
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    Write-GlazierLog -Level Change -Message "$label -> $Value"
    $script:GlazierChangeCount++
}

function Remove-GlazierRegistryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [string]$Description
    )
    $label = if ($Description) { $Description } else { "$Path\$Name" }

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-GlazierLog -Level Skip -Message "$label already absent"
        return
    }
    $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $item -or ($item.PSObject.Properties.Name -notcontains $Name)) {
        Write-GlazierLog -Level Skip -Message "$label already absent"
        return
    }
    if ($script:GlazierDryRun) {
        Write-GlazierLog -Level Change -Message "remove $label"
        $script:GlazierChangeCount++
        return
    }
    Remove-ItemProperty -LiteralPath $Path -Name $Name -Force
    Write-GlazierLog -Level Change -Message "remove $label"
    $script:GlazierChangeCount++
}

# --- Generic "perform an action unless dry-run" wrapper -----------------------
function Invoke-GlazierChange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    if ($script:GlazierDryRun) {
        Write-GlazierLog -Level Change -Message $Description
        $script:GlazierChangeCount++
        return
    }
    Write-GlazierLog -Level Change -Message $Description
    & $Action
    $script:GlazierChangeCount++
}

# --- Hardware / environment ---------------------------------------------------
function Test-GlazierNvidiaGpu {
    try {
        $gpus = Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop
        foreach ($gpu in $gpus) {
            if ($gpu.Name -match 'NVIDIA' -or $gpu.AdapterCompatibility -match 'NVIDIA') {
                return $true
            }
        }
    } catch {
        Write-GlazierLog -Level Warn -Message "Could not query GPUs: $($_.Exception.Message)"
    }
    return $false
}

function Get-GlazierRepositoryHome {
    param([string]$Preference = 'Auto')
    if ($Preference -and $Preference -ine 'Auto') {
        return $Preference
    }
    if (Test-Path -LiteralPath 'D:\') {
        return 'D:\Repositories'
    }
    return 'C:\Repositories'
}

function Restart-GlazierExplorer {
    if ($script:GlazierDryRun) {
        Write-GlazierLog -Level Change -Message 'restart explorer.exe'
        return
    }
    Write-GlazierLog -Level Info -Message 'Restarting Explorer to apply shell changes...'
    Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
        Start-Process explorer.exe
    }
}
