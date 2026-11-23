# =============================================================================
# DotNet.ps1 - .NET SDKs (via WinGet) and global EF Core tools
# =============================================================================
# Relies on Install-GlazierWingetPackage from Applications.ps1 (dot-sourced by
# Install.ps1 before this module).
# =============================================================================

Set-StrictMode -Version Latest

function Install-GlazierEfTools {
    Write-GlazierLog -Level Step -Message 'dotnet-ef global tool'

    $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
    if (-not $dotnet) {
        Write-GlazierLog -Level Warn -Message 'dotnet not on PATH yet (SDK just installed?). Open a new shell and re-run to add EF tools.'
        return
    }

    $installed = $false
    try {
        $list = & dotnet tool list --global 2>$null
        $installed = ($list | Select-String -SimpleMatch 'dotnet-ef' -Quiet) -eq $true
    } catch { }

    if ($script:GlazierDryRun) {
        $verb = if ($installed) { 'update' } else { 'install' }
        Write-GlazierLog -Level Change -Message "$verb dotnet-ef global tool"
        $script:GlazierChangeCount++
        return
    }

    if ($installed) {
        Write-GlazierLog -Level Skip -Message 'dotnet-ef already installed (leaving version as-is)'
        return
    }

    & dotnet tool install --global dotnet-ef
    if ($LASTEXITCODE -eq 0) {
        Write-GlazierLog -Level Change -Message 'installed dotnet-ef'
        $script:GlazierChangeCount++
    } else {
        Write-GlazierLog -Level Warn -Message "dotnet-ef install returned exit code $LASTEXITCODE"
    }
}

function Invoke-GlazierDotNet {
    param([Parameter(Mandatory)]$Config)

    Write-GlazierSection '.NET'

    if (-not (Test-GlazierEnabled -Config $Config -Key 'DotNet')) {
        Write-GlazierLog -Level Skip -Message 'DotNet section disabled'
        return
    }

    $sdks = Get-GlazierValue -Config $Config -Key 'DotNet.Sdks' -Default @()
    foreach ($sdk in $sdks) {
        $version = [string]$sdk
        if ([string]::IsNullOrWhiteSpace($version)) { continue }
        Install-GlazierWingetPackage -Id "Microsoft.DotNet.SDK.$version"
    }

    if (Get-GlazierValue -Config $Config -Key 'DotNet.EfTools' -Default $false) {
        Install-GlazierEfTools
    }
}
