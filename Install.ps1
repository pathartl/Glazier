<#
.SYNOPSIS
    Glazier - idempotent Windows 11 provisioning driven by a single YAML file.

.DESCRIPTION
    Reads glazier.yaml and applies each enabled feature section. Safe to run
    repeatedly: every step checks current state and only changes what is needed.

.PARAMETER ConfigPath
    Path to the YAML configuration. Defaults to .\glazier.yaml next to this script.

.PARAMETER DryRun
    Report what would change without modifying the system.

.PARAMETER NoElevate
    Do not attempt to self-elevate. Sections needing admin rights will be skipped
    or warn.

.PARAMETER Only
    Run only the named sections (e.g. -Only Applications,Theme). Section names
    match the top-level YAML keys.

.EXAMPLE
    .\Install.ps1
.EXAMPLE
    .\Install.ps1 -DryRun
.EXAMPLE
    .\Install.ps1 -ConfigPath .\glazier.local.yaml -Only Applications,DotNet
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'glazier.yaml'),
    [switch]$DryRun,
    [switch]$NoElevate,
    [string[]]$Only
)

$ErrorActionPreference = 'Stop'

# --- Self-elevation -----------------------------------------------------------
$here = $PSScriptRoot
. (Join-Path $here 'src\Common.ps1')   # for Test-GlazierAdmin (sets up $script:GlazierChangeCount too)

# Preserve the caller's dry-run choice for the elevated instance.
$script:GlazierDryRun = [bool]$DryRun

if (-not (Test-GlazierAdmin) -and -not $NoElevate) {
    Write-Host 'Glazier needs administrator rights for some sections; relaunching elevated...' -ForegroundColor Yellow
    $pwshExe = (Get-Process -Id $PID).Path   # same host that launched us (pwsh or powershell)
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-ConfigPath', "`"$ConfigPath`"")
    if ($DryRun) { $argList += '-DryRun' }
    if ($Only) { $argList += @('-Only', ($Only -join ',')) }
    try {
        Start-Process -FilePath $pwshExe -ArgumentList $argList -Verb RunAs
    } catch {
        Write-Host "Elevation was declined or failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host 'Re-run from an elevated terminal, or pass -NoElevate to continue unelevated.' -ForegroundColor Red
    }
    return
}

# --- Load library + modules ---------------------------------------------------
. (Join-Path $here 'src\Config.ps1')
$moduleDir = Join-Path $here 'src\Modules'
# Applications first (DotNet depends on its WinGet helper).
$moduleOrder = @(
    'Applications', 'WindowsFeatures', 'Taskbar', 'Explorer',
    'Copilot', 'Defaults', 'Theme', 'NetworkShares', 'DotNet', 'Fork'
)
foreach ($m in $moduleOrder) { . (Join-Path $moduleDir "$m.ps1") }

$toolsDir = Join-Path $here 'tools'

# --- Banner -------------------------------------------------------------------
Write-Host ''
Write-Host '  GLAZIER  ' -ForegroundColor Black -BackgroundColor Cyan -NoNewline
Write-Host '  Windows 11 provisioning' -ForegroundColor Cyan
if ($script:GlazierDryRun) {
    Write-Host '  (dry-run: no changes will be made)' -ForegroundColor Yellow
}
Write-Host "  Config: $ConfigPath" -ForegroundColor DarkGray
Write-Host "  Elevated: $(Test-GlazierAdmin)" -ForegroundColor DarkGray

# --- Config -------------------------------------------------------------------
$config = Import-GlazierConfig -Path $ConfigPath

# --- Section dispatch ---------------------------------------------------------
# Each entry: YAML key -> the function that applies it.
$sections = [ordered]@{
    'Applications'    = { Invoke-GlazierApplications -Config $config }
    'WindowsFeatures' = { Invoke-GlazierWindowsFeatures -Config $config }
    'Taskbar'         = { Invoke-GlazierTaskbar -Config $config }
    'Explorer'        = { Invoke-GlazierExplorer -Config $config }
    'Copilot'         = { Invoke-GlazierCopilot -Config $config }
    'Defaults'        = { Invoke-GlazierDefaults -Config $config -ToolsDir $toolsDir }
    'Theme'           = { Invoke-GlazierTheme -Config $config }
    'NetworkShares'   = { Invoke-GlazierNetworkShares -Config $config }
    'DotNet'          = { Invoke-GlazierDotNet -Config $config }
    'Fork'            = { Invoke-GlazierFork -Config $config }
}

$failures = @()
foreach ($name in $sections.Keys) {
    if ($Only -and ($Only -notcontains $name)) { continue }
    try {
        & $sections[$name]
    } catch {
        $failures += [PSCustomObject]@{ Section = $name; Error = $_.Exception.Message }
        Write-GlazierLog -Level Error -Message "Section '$name' failed: $($_.Exception.Message)"
    }
}

# --- Apply shell changes ------------------------------------------------------
$touchedShell = (-not $Only) -or ($Only | Where-Object { $_ -in @('Taskbar', 'Explorer', 'Theme') })
if ($touchedShell -and $script:GlazierChangeCount -gt 0 -and -not $script:GlazierDryRun) {
    Restart-GlazierExplorer
}

# --- Summary ------------------------------------------------------------------
Write-Host ''
Write-Host ('=' * 72) -ForegroundColor White
if ($script:GlazierDryRun) {
    Write-GlazierLog -Level Success -Message "Dry-run complete. $($script:GlazierChangeCount) change(s) would be applied."
} else {
    Write-GlazierLog -Level Success -Message "Done. $($script:GlazierChangeCount) change(s) applied."
}
if ($failures.Count -gt 0) {
    Write-GlazierLog -Level Warn -Message "$($failures.Count) section(s) reported errors:"
    foreach ($f in $failures) { Write-GlazierLog -Level Error -Message "  $($f.Section): $($f.Error)" }
}
Write-Host ''
Write-GlazierLog -Level Info -Message 'Notes:'
Write-GlazierLog -Level Info -Message '  - Taskbar pins apply at your next sign-in.'
Write-GlazierLog -Level Info -Message '  - Windows Sandbox / OpenSSH may require a reboot to finish.'
Write-GlazierLog -Level Info -Message '  - Sign out/in or reboot to ensure every shell tweak is visible.'
