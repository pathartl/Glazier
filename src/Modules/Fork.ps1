# =============================================================================
# Fork.ps1 - Fork (Git client) repository home
# =============================================================================
# Resolves the repository home (D:\Repositories when D: exists, else
# C:\Repositories), creates it, and writes Fork's default-repository setting.
#
# Fork keeps its settings in %APPDATA%\Fork\settings.json. The exact key name has
# changed between Fork versions, so the key is configurable (fork.settingsKey)
# and defaults to the common value. Verify in Fork > Preferences if it does not
# take effect.
# =============================================================================

Set-StrictMode -Version Latest

function Set-GlazierForkSetting {
    param(
        [Parameter(Mandatory)][string]$SettingsFile,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Value
    )

    $settings = [ordered]@{}
    if (Test-Path -LiteralPath $SettingsFile) {
        try {
            $existing = Get-Content -LiteralPath $SettingsFile -Raw | ConvertFrom-Json -ErrorAction Stop
            foreach ($prop in $existing.PSObject.Properties) { $settings[$prop.Name] = $prop.Value }
        } catch {
            Write-GlazierLog -Level Warn -Message "Existing Fork settings.json is not valid JSON; leaving it untouched."
            return
        }
    }

    if ($settings.Contains($Key) -and ("$($settings[$Key])" -eq $Value)) {
        Write-GlazierLog -Level Skip -Message "Fork '$Key' already = $Value"
        return
    }

    $settings[$Key] = $Value
    if ($script:GlazierDryRun) {
        Write-GlazierLog -Level Change -Message "set Fork '$Key' -> $Value"
        $script:GlazierChangeCount++
        return
    }

    $dir = Split-Path -Parent $SettingsFile
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    ($settings | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $SettingsFile -Encoding UTF8
    Write-GlazierLog -Level Change -Message "set Fork '$Key' -> $Value"
    $script:GlazierChangeCount++
}

function Invoke-GlazierFork {
    param([Parameter(Mandatory)]$Config)

    Write-GlazierSection 'Fork (Git client)'

    if (-not (Test-GlazierEnabled -Config $Config -Key 'Fork')) {
        Write-GlazierLog -Level Skip -Message 'Fork section disabled'
        return
    }

    $preference = [string](Get-GlazierValue -Config $Config -Key 'Fork.RepositoryHome' -Default 'auto')
    $repoHome = Get-GlazierRepositoryHome -Preference $preference
    Write-GlazierLog -Level Info -Message "Repository home resolved to: $repoHome"

    if (Get-GlazierValue -Config $Config -Key 'Fork.CreateDirectory' -Default $true) {
        if (Test-Path -LiteralPath $repoHome) {
            Write-GlazierLog -Level Skip -Message "$repoHome already exists"
        } elseif ($script:GlazierDryRun) {
            Write-GlazierLog -Level Change -Message "create $repoHome"
            $script:GlazierChangeCount++
        } else {
            New-Item -ItemType Directory -Path $repoHome -Force | Out-Null
            Write-GlazierLog -Level Change -Message "created $repoHome"
            $script:GlazierChangeCount++
        }
    }

    $settingsFile = [string](Get-GlazierValue -Config $Config -Key 'Fork.SettingsFile' `
            -Default (Join-Path $env:APPDATA 'Fork\settings.json'))
    $settingsKey = [string](Get-GlazierValue -Config $Config -Key 'Fork.SettingsKey' `
            -Default 'defaultRepositoryPath')
    Set-GlazierForkSetting -SettingsFile $settingsFile -Key $settingsKey -Value $repoHome
}
