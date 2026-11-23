# =============================================================================
# Applications.ps1 - install applications via WinGet
# =============================================================================

Set-StrictMode -Version Latest

function Test-GlazierWingetInstalled {
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$Source = 'winget'
    )
    # `winget list --id X -e` exits 0 when the package is present. We also match
    # the id in the output as a guard against partial/no-source matches.
    $output = winget list --id $Id -e --source $Source --disable-interactivity 2>$null
    if ($LASTEXITCODE -ne 0) { return $false }
    return ($output | Select-String -SimpleMatch $Id -Quiet) -eq $true
}

function Install-GlazierWingetPackage {
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$Source = 'winget'
    )

    if (Test-GlazierWingetInstalled -Id $Id -Source $Source) {
        Write-GlazierLog -Level Skip -Message "$Id already installed"
        return
    }

    if ($script:GlazierDryRun) {
        Write-GlazierLog -Level Change -Message "install $Id (source: $Source)"
        $script:GlazierChangeCount++
        return
    }

    Write-GlazierLog -Level Change -Message "install $Id (source: $Source)"
    winget install --id $Id -e --source $Source `
        --accept-package-agreements --accept-source-agreements `
        --silent --disable-interactivity

    $code = $LASTEXITCODE
    # 0 = success. Some "already installed / no applicable update" states surface
    # as non-zero; re-check presence before declaring failure.
    if ($code -eq 0 -or (Test-GlazierWingetInstalled -Id $Id -Source $Source)) {
        $script:GlazierChangeCount++
    } else {
        Write-GlazierLog -Level Warn -Message "$Id install returned exit code $code"
    }
}

function Invoke-GlazierApplications {
    param([Parameter(Mandatory)]$Config)

    Write-GlazierSection 'Applications (WinGet)'

    if (-not (Test-GlazierEnabled -Config $Config -Key 'Applications')) {
        Write-GlazierLog -Level Skip -Message 'applications section disabled'
        return
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-GlazierLog -Level Error -Message 'winget not found. Install "App Installer" from the Microsoft Store, then re-run.'
        return
    }

    # --- Core packages --------------------------------------------------------
    $packages = Get-GlazierValue -Config $Config -Key 'Applications.Packages' -Default @()
    foreach ($pkg in $packages) {
        $id = [string]$pkg['Id']
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        $source = if ($pkg.Contains('Source')) { [string]$pkg['Source'] } else { 'winget' }
        Install-GlazierWingetPackage -Id $id -Source $source
    }

    # --- Gaming redistributables ---------------------------------------------
    if (Test-GlazierEnabled -Config $Config -Key 'Applications.GamingRedistributables') {
        Write-GlazierLog -Level Step -Message 'Gaming redistributables'
        $redists = Get-GlazierValue -Config $Config -Key 'Applications.GamingRedistributables.Packages' -Default @()
        foreach ($pkg in $redists) {
            $id = [string]$pkg['Id']
            if ([string]::IsNullOrWhiteSpace($id)) { continue }
            Install-GlazierWingetPackage -Id $id
        }
    }

    # --- NVIDIA App -----------------------------------------------------------
    $nvMode = [string](Get-GlazierValue -Config $Config -Key 'Applications.NvidiaApp.Mode' -Default 'Auto')
    if ($nvMode -ine 'Never') {
        $install = $false
        if ($nvMode -ieq 'Always') {
            $install = $true
        } elseif ($nvMode -ieq 'Auto') {
            if (Test-GlazierNvidiaGpu) {
                $install = $true
                Write-GlazierLog -Level Info -Message 'NVIDIA GPU detected'
            } else {
                Write-GlazierLog -Level Skip -Message 'No NVIDIA GPU detected; skipping NVIDIA App'
            }
        }
        if ($install) {
            $nvId = [string](Get-GlazierValue -Config $Config -Key 'Applications.NvidiaApp.Id' -Default 'XP8CLZL93F5Z4P')
            $nvSrc = [string](Get-GlazierValue -Config $Config -Key 'Applications.NvidiaApp.Source' -Default 'msstore')
            Install-GlazierWingetPackage -Id $nvId -Source $nvSrc
        }
    }
}
