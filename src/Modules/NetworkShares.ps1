# =============================================================================
# NetworkShares.ps1 - mount SMB shares, prompting for credentials at runtime
# =============================================================================
# Passwords are never read from the config; they are prompted for when the share
# is not already connected.
# =============================================================================

Set-StrictMode -Version Latest

function Test-GlazierShareMapped {
    param([Parameter(Mandatory)][string]$RemotePath)
    $mapping = Get-SmbMapping -RemotePath $RemotePath -ErrorAction SilentlyContinue
    return $null -ne $mapping
}

function Mount-GlazierShare {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$DriveLetter = '',
        [bool]$Persistent = $true,
        [bool]$PromptForPassword = $true,
        [string]$Username = ''
    )

    if (Test-GlazierShareMapped -RemotePath $Path) {
        Write-GlazierLog -Level Skip -Message "$Path already mapped"
        return
    }

    if ($script:GlazierDryRun) {
        $where = if ($DriveLetter) { "$DriveLetter`: -> $Path" } else { $Path }
        Write-GlazierLog -Level Change -Message "mount $where (persistent=$Persistent)"
        $script:GlazierChangeCount++
        return
    }

    $params = @{
        RemotePath  = $Path
        Persistent  = $Persistent
        ErrorAction = 'Stop'
    }
    if ($DriveLetter) { $params['LocalPath'] = ($DriveLetter.TrimEnd(':') + ':') }

    if ($PromptForPassword) {
        $message = "Credentials for $Path"
        $cred = if ($Username) {
            Get-Credential -UserName $Username -Message $message
        } else {
            Get-Credential -Message $message
        }
        if ($null -eq $cred) {
            Write-GlazierLog -Level Warn -Message "No credentials entered; skipping $Path"
            return
        }
        $params['UserName'] = $cred.UserName
        $params['Password'] = $cred.GetNetworkCredential().Password
    } elseif ($Username) {
        $params['UserName'] = $Username
    }

    try {
        New-SmbMapping @params | Out-Null
        Write-GlazierLog -Level Change -Message "mounted $Path"
        $script:GlazierChangeCount++
    } catch {
        Write-GlazierLog -Level Error -Message "Failed to mount $Path`: $($_.Exception.Message)"
    }
}

function Invoke-GlazierNetworkShares {
    param([Parameter(Mandatory)]$Config)

    Write-GlazierSection 'Network Shares'

    if (-not (Test-GlazierEnabled -Config $Config -Key 'NetworkShares')) {
        Write-GlazierLog -Level Skip -Message 'NetworkShares section disabled'
        return
    }

    $shares = Get-GlazierValue -Config $Config -Key 'NetworkShares.Shares' -Default @()
    if (@($shares).Count -eq 0) {
        Write-GlazierLog -Level Skip -Message 'no shares configured'
        return
    }

    foreach ($share in $shares) {
        $path = [string]$share['Path']
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        $letter = if ($share.Contains('DriveLetter')) { [string]$share['DriveLetter'] } else { '' }
        $persistent = if ($share.Contains('Persistent')) { [bool]$share['Persistent'] } else { $true }
        $prompt = if ($share.Contains('PromptForPassword')) { [bool]$share['PromptForPassword'] } else { $true }
        $user = if ($share.Contains('Username')) { [string]$share['Username'] } else { '' }

        Mount-GlazierShare -Path $path -DriveLetter $letter -Persistent $persistent `
            -PromptForPassword $prompt -Username $user
    }
}
