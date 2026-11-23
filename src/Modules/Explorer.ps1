# =============================================================================
# Explorer.ps1 - File Explorer view options and Quick Access
# =============================================================================

Set-StrictMode -Version Latest

$script:ExplorerAdvanced = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

function Add-GlazierQuickAccessPin {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-GlazierLog -Level Warn -Message "Cannot pin to Quick Access, path missing: $Path"
        return
    }

    # Quick Access pins live in an opaque automatic-destinations file; there is no
    # clean read API, so we check the live Quick Access namespace for the folder.
    $alreadyPinned = $false
    try {
        $shell = New-Object -ComObject shell.application
        $qa = $shell.Namespace('shell:::{679f85cb-0220-4080-b29b-5540cc05aab6}')
        if ($qa) {
            foreach ($item in $qa.Items()) {
                if ($item.IsFolder -and ($item.Path -ieq $Path)) { $alreadyPinned = $true; break }
            }
        }
    } catch {
        # Fall through and attempt the pin regardless.
    }

    if ($alreadyPinned) {
        Write-GlazierLog -Level Skip -Message "Quick Access already contains $Path"
        return
    }
    if ($script:GlazierDryRun) {
        Write-GlazierLog -Level Change -Message "pin $Path to Quick Access"
        $script:GlazierChangeCount++
        return
    }

    try {
        $shell = New-Object -ComObject shell.application
        $shell.Namespace($Path).Self.InvokeVerb('pintohome')
        Write-GlazierLog -Level Change -Message "pinned $Path to Quick Access"
        Write-GlazierLog -Level Info -Message 'Quick Access order is not script-controllable; drag it to the top if needed.'
        $script:GlazierChangeCount++
    } catch {
        Write-GlazierLog -Level Warn -Message "Could not pin to Quick Access: $($_.Exception.Message)"
    }
}

function Invoke-GlazierExplorer {
    param([Parameter(Mandatory)]$Config)

    Write-GlazierSection 'File Explorer'

    if (-not (Test-GlazierEnabled -Config $Config -Key 'Explorer')) {
        Write-GlazierLog -Level Skip -Message 'Explorer section disabled'
        return
    }

    if (Get-GlazierValue -Config $Config -Key 'Explorer.ShowHiddenFiles' -Default $false) {
        Set-GlazierRegistryValue -Path $script:ExplorerAdvanced -Name 'Hidden' -Value 1 `
            -Description 'Show hidden files'
    }
    if (Get-GlazierValue -Config $Config -Key 'Explorer.ShowSystemFiles' -Default $false) {
        Set-GlazierRegistryValue -Path $script:ExplorerAdvanced -Name 'ShowSuperHidden' -Value 1 `
            -Description 'Show protected OS (system) files'
    }
    if (Get-GlazierValue -Config $Config -Key 'Explorer.ShowFileExtensions' -Default $false) {
        Set-GlazierRegistryValue -Path $script:ExplorerAdvanced -Name 'HideFileExt' -Value 0 `
            -Description 'Show file extensions'
    }
    if (Get-GlazierValue -Config $Config -Key 'Explorer.PinHomeToQuickAccess' -Default $false) {
        Write-GlazierLog -Level Step -Message 'Quick Access'
        Add-GlazierQuickAccessPin -Path $env:USERPROFILE
    }
}
