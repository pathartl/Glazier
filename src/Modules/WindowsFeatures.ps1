# =============================================================================
# WindowsFeatures.ps1 - Sandbox, Remote Desktop, OpenSSH Server
# =============================================================================
# All operations here require an elevated session.
# =============================================================================

Set-StrictMode -Version Latest

function Enable-GlazierOptionalFeature {
    param(
        [Parameter(Mandatory)][string]$FeatureName,
        [Parameter(Mandatory)][string]$FriendlyName
    )
    $feature = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction SilentlyContinue
    if ($null -eq $feature) {
        Write-GlazierLog -Level Warn -Message "$FriendlyName feature ($FeatureName) is not available on this edition"
        return
    }
    if ($feature.State -eq 'Enabled') {
        Write-GlazierLog -Level Skip -Message "$FriendlyName already enabled"
        return
    }
    if ($script:GlazierDryRun) {
        Write-GlazierLog -Level Change -Message "enable $FriendlyName"
        $script:GlazierChangeCount++
        return
    }
    Write-GlazierLog -Level Change -Message "enable $FriendlyName (a reboot may be required)"
    Enable-WindowsOptionalFeature -Online -FeatureName $FeatureName -All -NoRestart -ErrorAction Stop | Out-Null
    $script:GlazierChangeCount++
}

function Enable-GlazierRemoteDesktop {
    Write-GlazierLog -Level Step -Message 'Remote Desktop'
    Set-GlazierRegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' `
        -Name 'fDenyTSConnections' -Value 0 -Type DWord -Description 'Allow RDP connections'

    # Network Level Authentication on.
    Set-GlazierRegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
        -Name 'UserAuthentication' -Value 1 -Type DWord -Description 'Require NLA for RDP'

    if ($script:GlazierDryRun) {
        Write-GlazierLog -Level Change -Message 'enable Remote Desktop firewall group'
        return
    }
    try {
        Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction Stop
        Write-GlazierLog -Level Change -Message 'enabled Remote Desktop firewall group'
    } catch {
        Write-GlazierLog -Level Warn -Message "Could not enable RDP firewall rules: $($_.Exception.Message)"
    }
}

function Install-GlazierOpenSshServer {
    Write-GlazierLog -Level Step -Message 'OpenSSH Server'
    $cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $cap) {
        Write-GlazierLog -Level Warn -Message 'OpenSSH.Server capability not available'
        return
    }

    if ($cap.State -ne 'Installed') {
        if ($script:GlazierDryRun) {
            Write-GlazierLog -Level Change -Message "install $($cap.Name)"
            $script:GlazierChangeCount++
        } else {
            Write-GlazierLog -Level Change -Message "install $($cap.Name)"
            Add-WindowsCapability -Online -Name $cap.Name -ErrorAction Stop | Out-Null
            $script:GlazierChangeCount++
        }
    } else {
        Write-GlazierLog -Level Skip -Message 'OpenSSH Server already installed'
    }

    if ($script:GlazierDryRun) {
        Write-GlazierLog -Level Change -Message 'set sshd service to Automatic and start it'
        return
    }

    # Service: automatic start + running.
    $svc = Get-Service -Name sshd -ErrorAction SilentlyContinue
    if ($svc) {
        if ((Get-CimInstance Win32_Service -Filter "Name='sshd'").StartMode -ne 'Auto') {
            Set-Service -Name sshd -StartupType Automatic
            Write-GlazierLog -Level Change -Message 'sshd start type -> Automatic'
        } else {
            Write-GlazierLog -Level Skip -Message 'sshd already Automatic'
        }
        if ($svc.Status -ne 'Running') {
            Start-Service sshd
            Write-GlazierLog -Level Change -Message 'started sshd'
        } else {
            Write-GlazierLog -Level Skip -Message 'sshd already running'
        }
    } else {
        Write-GlazierLog -Level Warn -Message 'sshd service not present yet (install may need a reboot)'
    }

    # Firewall rule (the capability usually adds this; ensure it exists).
    if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' `
            -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
        Write-GlazierLog -Level Change -Message 'added OpenSSH inbound firewall rule'
    } else {
        Write-GlazierLog -Level Skip -Message 'OpenSSH firewall rule already present'
    }
}

function Invoke-GlazierWindowsFeatures {
    param([Parameter(Mandatory)]$Config)

    Write-GlazierSection 'Windows Features & Services'

    if (-not (Test-GlazierEnabled -Config $Config -Key 'WindowsFeatures')) {
        Write-GlazierLog -Level Skip -Message 'WindowsFeatures section disabled'
        return
    }

    if (-not (Test-GlazierAdmin)) {
        Write-GlazierLog -Level Warn -Message 'Not elevated; skipping Windows features/services (run elevated to apply).'
        return
    }

    if (Get-GlazierValue -Config $Config -Key 'WindowsFeatures.Sandbox' -Default $false) {
        Enable-GlazierOptionalFeature -FeatureName 'Containers-DisposableClientVM' -FriendlyName 'Windows Sandbox'
    }
    if (Get-GlazierValue -Config $Config -Key 'WindowsFeatures.RemoteDesktop' -Default $false) {
        Enable-GlazierRemoteDesktop
    }
    if (Get-GlazierValue -Config $Config -Key 'WindowsFeatures.OpenSshServer' -Default $false) {
        Install-GlazierOpenSshServer
    }
}
