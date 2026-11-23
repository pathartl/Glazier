# =============================================================================
# Defaults.ps1 - default browser, archive associations, Terminal shell
# =============================================================================
# Windows 11 protects the default-apps choice with a per-user hash that scripts
# cannot write directly. Glazier uses SetUserFTA (https://kolbi.cz/) to set file
# and protocol associations. The download is opt-in (defaults.useSetUserFTA).
# =============================================================================

Set-StrictMode -Version Latest

# Well-known GUID of the auto-generated Windows Terminal PowerShell 7 profile.
$script:Pwsh7ProfileGuid = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'

# --- SetUserFTA bootstrap -----------------------------------------------------
function Get-GlazierSetUserFta {
    param(
        [Parameter(Mandatory)][string]$ToolsDir,
        [Parameter(Mandatory)][string]$Url
    )

    $exe = Get-ChildItem -LiteralPath $ToolsDir -Recurse -Filter 'SetUserFTA.exe' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($exe) { return $exe.FullName }

    if ($script:GlazierDryRun) {
        Write-GlazierLog -Level Change -Message "download SetUserFTA from $Url"
        return $null
    }

    Write-GlazierLog -Level Change -Message "downloading SetUserFTA from $Url"
    try {
        [Net.ServicePointManager]::SecurityProtocol = `
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }

    $zip = Join-Path $ToolsDir 'SetUserFTA.zip'
    $extractDir = Join-Path $ToolsDir 'SetUserFTA'
    try {
        if (-not (Test-Path -LiteralPath $ToolsDir)) { New-Item -ItemType Directory -Path $ToolsDir -Force | Out-Null }
        Invoke-WebRequest -Uri $Url -OutFile $zip -UseBasicParsing -ErrorAction Stop
        if (Test-Path -LiteralPath $extractDir) { Remove-Item -LiteralPath $extractDir -Recurse -Force }
        Expand-Archive -LiteralPath $zip -DestinationPath $extractDir -Force
    } catch {
        Write-GlazierLog -Level Error -Message "Failed to obtain SetUserFTA: $($_.Exception.Message)"
        return $null
    }

    $exe = Get-ChildItem -LiteralPath $extractDir -Recurse -Filter 'SetUserFTA.exe' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $exe) {
        Write-GlazierLog -Level Error -Message 'SetUserFTA.exe not found in the downloaded archive'
        return $null
    }
    $script:GlazierChangeCount++
    return $exe.FullName
}

function Invoke-GlazierSetUserFta {
    param(
        [AllowEmptyString()][string]$ExePath,
        [Parameter(Mandatory)][string]$Target,   # extension (.html) or protocol (http)
        [Parameter(Mandatory)][string]$ProgId
    )
    if ($script:GlazierDryRun) {
        Write-GlazierLog -Level Change -Message "associate $Target -> $ProgId"
        $script:GlazierChangeCount++
        return
    }
    if ([string]::IsNullOrEmpty($ExePath)) {
        Write-GlazierLog -Level Warn -Message "SetUserFTA unavailable; cannot associate $Target"
        return
    }
    & $ExePath $Target $ProgId | Out-Null
    Write-GlazierLog -Level Change -Message "associated $Target -> $ProgId"
    $script:GlazierChangeCount++
}

# --- Browser capabilities discovery ------------------------------------------
# Reads a registered browser's URL/file associations (ProgIds) from its
# Capabilities key so we never hard-code the per-install ProgId hash.
function Get-GlazierBrowserAssociations {
    param([Parameter(Mandatory)][string]$Name)

    $result = @{ Url = @{}; File = @{} }
    $clientsRoot = 'HKLM:\SOFTWARE\Clients\StartMenuInternet'
    if (-not (Test-Path -LiteralPath $clientsRoot)) { return $result }

    foreach ($client in Get-ChildItem -LiteralPath $clientsRoot -ErrorAction SilentlyContinue) {
        $capPath = Join-Path $client.PSPath 'Capabilities'
        if (-not (Test-Path -LiteralPath $capPath)) { continue }
        $cap = Get-ItemProperty -LiteralPath $capPath -ErrorAction SilentlyContinue
        $appName = if ($cap -and ($cap.PSObject.Properties.Name -contains 'ApplicationName')) { $cap.ApplicationName } else { $client.PSChildName }
        if ($appName -notmatch [regex]::Escape($Name) -and $client.PSChildName -notmatch [regex]::Escape($Name)) { continue }

        $urlPath = Join-Path $capPath 'URLAssociations'
        if (Test-Path -LiteralPath $urlPath) {
            $props = Get-ItemProperty -LiteralPath $urlPath
            foreach ($p in $props.PSObject.Properties) {
                if ($p.Name -notlike 'PS*') { $result.Url[$p.Name] = $p.Value }
            }
        }
        $filePath = Join-Path $capPath 'FileAssociations'
        if (Test-Path -LiteralPath $filePath) {
            $props = Get-ItemProperty -LiteralPath $filePath
            foreach ($p in $props.PSObject.Properties) {
                if ($p.Name -notlike 'PS*') { $result.File[$p.Name] = $p.Value }
            }
        }
        break
    }
    return $result
}

# --- NanaZip ProgId discovery -------------------------------------------------
function Resolve-GlazierNanaZipProgId {
    param([Parameter(Mandatory)][string]$Extension)

    $extNoDot = $Extension.TrimStart('.')
    $titleCase = if ($extNoDot.Length -gt 0) {
        $extNoDot.Substring(0, 1).ToUpper() + $extNoDot.Substring(1).ToLower()
    } else { $extNoDot }

    $candidates = @("NanaZip.$titleCase", "NanaZip.$extNoDot", "NanaZip.$($extNoDot.ToLower())")
    foreach ($c in ($candidates | Select-Object -Unique)) {
        if ((Test-Path "Registry::HKEY_CLASSES_ROOT\$c") -or
            (Test-Path "HKCU:\Software\Classes\$c")) {
            return $c
        }
    }
    return $null
}

# --- Windows Terminal default profile ----------------------------------------
function Set-GlazierTerminalDefaultProfile {
    param([Parameter(Mandatory)][string]$Guid)

    Write-GlazierLog -Level Step -Message 'Windows Terminal default profile'
    $settings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    if (-not (Test-Path -LiteralPath $settings)) {
        Write-GlazierLog -Level Warn -Message 'Windows Terminal settings.json not found. Launch Terminal once, then re-run.'
        return
    }

    $raw = Get-Content -LiteralPath $settings -Raw
    $match = [regex]::Match($raw, '"defaultProfile"\s*:\s*"([^"]*)"')
    if (-not $match.Success) {
        Write-GlazierLog -Level Warn -Message 'Could not locate defaultProfile in settings.json; leaving it unchanged.'
        return
    }
    if ($match.Groups[1].Value -ieq $Guid) {
        Write-GlazierLog -Level Skip -Message 'Terminal default profile already PowerShell 7'
        return
    }
    if ($script:GlazierDryRun) {
        Write-GlazierLog -Level Change -Message "Terminal defaultProfile -> $Guid"
        $script:GlazierChangeCount++
        return
    }
    $updated = $raw.Substring(0, $match.Groups[1].Index) + $Guid + $raw.Substring($match.Groups[1].Index + $match.Groups[1].Length)
    Set-Content -LiteralPath $settings -Value $updated -Encoding UTF8 -NoNewline
    Write-GlazierLog -Level Change -Message 'set Terminal default profile to PowerShell 7'
    $script:GlazierChangeCount++
}

function Invoke-GlazierDefaults {
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$ToolsDir
    )

    Write-GlazierSection 'Default Applications'

    if (-not (Test-GlazierEnabled -Config $Config -Key 'Defaults')) {
        Write-GlazierLog -Level Skip -Message 'Defaults section disabled'
        return
    }

    $useFta = [bool](Get-GlazierValue -Config $Config -Key 'Defaults.UseSetUserFTA' -Default $true)
    $ftaUrl = [string](Get-GlazierValue -Config $Config -Key 'Defaults.SetUserFtaUrl' -Default 'https://kolbi.cz/SetUserFTA.zip')
    $ftaExe = $null

    $needsFta = (Test-GlazierEnabled -Config $Config -Key 'Defaults.Browser') -or
                (Test-GlazierEnabled -Config $Config -Key 'Defaults.ArchiveTool')

    if ($needsFta) {
        if ($useFta) {
            $ftaExe = Get-GlazierSetUserFta -ToolsDir $ToolsDir -Url $ftaUrl
            if (-not $ftaExe -and -not $script:GlazierDryRun) {
                Write-GlazierLog -Level Warn -Message 'SetUserFTA unavailable; skipping association changes.'
            }
        } else {
            Write-GlazierLog -Level Warn -Message 'defaults.useSetUserFTA is false; browser/archive associations will be skipped.'
        }
    }

    # --- Browser ---
    if ((Test-GlazierEnabled -Config $Config -Key 'Defaults.Browser') -and ($ftaExe -or $script:GlazierDryRun)) {
        $browserName = [string](Get-GlazierValue -Config $Config -Key 'Defaults.Browser.Name' -Default 'Firefox')
        Write-GlazierLog -Level Step -Message "Default browser ($browserName)"
        $assoc = Get-GlazierBrowserAssociations -Name $browserName
        if ($assoc.Url.Count -eq 0 -and $assoc.File.Count -eq 0 -and -not $script:GlazierDryRun) {
            Write-GlazierLog -Level Warn -Message "$browserName is not registered yet (install it first); skipping browser default."
        } else {
            foreach ($proto in @('http', 'https')) {
                if ($assoc.Url.ContainsKey($proto)) {
                    Invoke-GlazierSetUserFta -ExePath $ftaExe -Target $proto -ProgId $assoc.Url[$proto]
                }
            }
            foreach ($ext in @('.htm', '.html', '.shtml', '.svg', '.xht', '.xhtml')) {
                if ($assoc.File.ContainsKey($ext)) {
                    Invoke-GlazierSetUserFta -ExePath $ftaExe -Target $ext -ProgId $assoc.File[$ext]
                }
            }
            # Dry-run illustration when nothing is registered yet.
            if ($script:GlazierDryRun -and $assoc.Url.Count -eq 0) {
                Write-GlazierLog -Level Info -Message '(dry-run) would associate http/https/.html with the browser ProgId once installed.'
            }
        }
    }

    # --- Archive tool (NanaZip) ---
    if ((Test-GlazierEnabled -Config $Config -Key 'Defaults.ArchiveTool') -and ($ftaExe -or $script:GlazierDryRun)) {
        $toolName = [string](Get-GlazierValue -Config $Config -Key 'Defaults.ArchiveTool.Name' -Default 'NanaZip')
        Write-GlazierLog -Level Step -Message "Default archive tool ($toolName)"
        $exts = Get-GlazierValue -Config $Config -Key 'Defaults.ArchiveTool.Extensions' -Default @()
        foreach ($ext in $exts) {
            $e = [string]$ext
            if ([string]::IsNullOrWhiteSpace($e)) { continue }
            if (-not $e.StartsWith('.')) { $e = ".$e" }
            $progId = Resolve-GlazierNanaZipProgId -Extension $e
            if (-not $progId) {
                if ($script:GlazierDryRun) {
                    Write-GlazierLog -Level Info -Message "(dry-run) would associate $e with the NanaZip ProgId once installed."
                } else {
                    Write-GlazierLog -Level Warn -Message "No NanaZip ProgId registered for $e; skipping (open NanaZip once to register types)."
                }
                continue
            }
            Invoke-GlazierSetUserFta -ExePath $ftaExe -Target $e -ProgId $progId
        }
    }

    # --- Terminal default shell ---
    if (Test-GlazierEnabled -Config $Config -Key 'Defaults.TerminalShell') {
        $shell = [string](Get-GlazierValue -Config $Config -Key 'Defaults.TerminalShell.Shell' -Default 'PowerShell7')
        if ($shell -ieq 'PowerShell7') {
            Set-GlazierTerminalDefaultProfile -Guid $script:Pwsh7ProfileGuid
        } else {
            Write-GlazierLog -Level Warn -Message "Unsupported terminalShell '$shell'; only PowerShell7 is handled."
        }
    }
}
