# =============================================================================
# Taskbar.ps1 - alignment, button visibility, and pinned apps
# =============================================================================
# Button/alignment tweaks are per-user registry values under Explorer\Advanced.
# Pins are written to a per-user LayoutModification.xml. NOTE: on Windows 11,
# taskbar pins declared this way are applied at the next sign-in, not live.
# =============================================================================

Set-StrictMode -Version Latest

$script:TaskbarAdvanced = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$script:TaskbarSearch = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'

# Known "name -> taskbar pin target" resolution. Explorer is a shell app with a
# fixed AppUserModelID; everything else is resolved from a Start Menu shortcut.
function Resolve-GlazierPinTarget {
    param([Parameter(Mandatory)][string]$Name)

    if ($Name -ieq 'Explorer' -or $Name -ieq 'File Explorer') {
        return [PSCustomObject]@{ Kind = 'Aumid'; Value = 'Microsoft.Windows.Explorer' }
    }

    $roots = @(
        [Environment]::GetFolderPath('StartMenu'),
        [Environment]::GetFolderPath('CommonStartMenu')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    foreach ($root in $roots) {
        # Prefer an exact "<Name>.lnk", then any shortcut containing the name.
        $exact = Get-ChildItem -LiteralPath $root -Recurse -Filter '*.lnk' -ErrorAction SilentlyContinue |
            Where-Object { $_.BaseName -ieq $Name } | Select-Object -First 1
        if ($exact) { return [PSCustomObject]@{ Kind = 'Link'; Value = $exact.FullName } }
    }
    foreach ($root in $roots) {
        $partial = Get-ChildItem -LiteralPath $root -Recurse -Filter '*.lnk' -ErrorAction SilentlyContinue |
            Where-Object { $_.BaseName -like "*$Name*" } | Select-Object -First 1
        if ($partial) { return [PSCustomObject]@{ Kind = 'Link'; Value = $partial.FullName } }
    }
    return $null
}

function New-GlazierTaskbarLayoutXml {
    param([Parameter(Mandatory)][string[]]$Apps)

    $entries = New-Object System.Collections.Generic.List[string]
    foreach ($app in $Apps) {
        $target = Resolve-GlazierPinTarget -Name $app
        if ($null -eq $target) {
            Write-GlazierLog -Level Warn -Message "Taskbar pin '$app' could not be resolved (no shortcut found); skipping"
            continue
        }
        if ($target.Kind -eq 'Aumid') {
            $entries.Add("        <taskbar:DesktopApp DesktopApplicationID=`"$($target.Value)`" />")
        } else {
            $entries.Add("        <taskbar:DesktopApp DesktopApplicationLinkPath=`"$($target.Value)`" />")
        }
        Write-GlazierLog -Level Info -Message "Taskbar pin resolved: $app -> $($target.Value)"
    }

    $pinBlock = $entries -join "`r`n"
    return @"
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate
    xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification"
    xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout"
    xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout"
    xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout"
    Version="1">
  <CustomTaskbarLayoutCollection PinListPlacement="Replace">
    <defaultlayout:TaskbarLayout>
      <taskbar:TaskbarPinList>
$pinBlock
      </taskbar:TaskbarPinList>
    </defaultlayout:TaskbarLayout>
  </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
"@
}

function Set-GlazierTaskbarPins {
    param([Parameter(Mandatory)][string[]]$Apps)

    Write-GlazierLog -Level Step -Message 'Taskbar pins'
    $xml = New-GlazierTaskbarLayoutXml -Apps $Apps
    $shellDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Shell'
    $target = Join-Path $shellDir 'LayoutModification.xml'

    $existing = if (Test-Path -LiteralPath $target) { Get-Content -LiteralPath $target -Raw } else { '' }
    if ($existing.Trim() -eq $xml.Trim()) {
        Write-GlazierLog -Level Skip -Message 'taskbar layout already up to date'
        return
    }

    if ($script:GlazierDryRun) {
        Write-GlazierLog -Level Change -Message "write $target"
        $script:GlazierChangeCount++
        return
    }
    if (-not (Test-Path -LiteralPath $shellDir)) {
        New-Item -ItemType Directory -Path $shellDir -Force | Out-Null
    }
    Set-Content -LiteralPath $target -Value $xml -Encoding UTF8
    Write-GlazierLog -Level Change -Message "wrote taskbar layout -> $target"
    Write-GlazierLog -Level Warn -Message 'Taskbar pins apply at your next sign-in (Windows 11 limitation).'
    $script:GlazierChangeCount++
}

function Invoke-GlazierTaskbar {
    param([Parameter(Mandatory)]$Config)

    Write-GlazierSection 'Taskbar'

    if (-not (Test-GlazierEnabled -Config $Config -Key 'Taskbar')) {
        Write-GlazierLog -Level Skip -Message 'Taskbar section disabled'
        return
    }

    $alignment = [string](Get-GlazierValue -Config $Config -Key 'Taskbar.Alignment' -Default 'Left')
    $alValue = if ($alignment -ieq 'Left') { 0 } else { 1 }
    Set-GlazierRegistryValue -Path $script:TaskbarAdvanced -Name 'TaskbarAl' -Value $alValue `
        -Description "Taskbar alignment ($alignment)"

    if (Get-GlazierValue -Config $Config -Key 'Taskbar.RemoveSearch' -Default $false) {
        Set-GlazierRegistryValue -Path $script:TaskbarSearch -Name 'SearchboxTaskbarMode' -Value 0 `
            -Description 'Hide taskbar search'
    }
    if (Get-GlazierValue -Config $Config -Key 'Taskbar.RemoveTaskView' -Default $false) {
        Set-GlazierRegistryValue -Path $script:TaskbarAdvanced -Name 'ShowTaskViewButton' -Value 0 `
            -Description 'Hide Task View button'
    }
    if (Get-GlazierValue -Config $Config -Key 'Taskbar.RemoveWidgets' -Default $false) {
        Set-GlazierRegistryValue -Path $script:TaskbarAdvanced -Name 'TaskbarDa' -Value 0 `
            -Description 'Hide Widgets button'
    }
    if (Get-GlazierValue -Config $Config -Key 'Taskbar.RemoveCopilotButton' -Default $false) {
        Set-GlazierRegistryValue -Path $script:TaskbarAdvanced -Name 'ShowCopilotButton' -Value 0 `
            -Description 'Hide Copilot button'
    }

    if (Test-GlazierEnabled -Config $Config -Key 'Taskbar.Pins') {
        $apps = Get-GlazierValue -Config $Config -Key 'Taskbar.Pins.Apps' -Default @()
        $appNames = @($apps | ForEach-Object { [string]$_ } | Where-Object { $_ })
        if ($appNames.Count -gt 0) {
            Set-GlazierTaskbarPins -Apps $appNames
        }
    }
}
