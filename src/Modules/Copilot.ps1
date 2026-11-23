# =============================================================================
# Copilot.ps1 - disable and remove Windows Copilot
# =============================================================================

Set-StrictMode -Version Latest

function Invoke-GlazierCopilot {
    param([Parameter(Mandatory)]$Config)

    Write-GlazierSection 'Copilot removal'

    if (-not (Test-GlazierEnabled -Config $Config -Key 'Copilot')) {
        Write-GlazierLog -Level Skip -Message 'Copilot section disabled'
        return
    }

    if (Get-GlazierValue -Config $Config -Key 'Copilot.DisablePolicy' -Default $true) {
        # Per-user policy.
        Set-GlazierRegistryValue -Path 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' `
            -Name 'TurnOffWindowsCopilot' -Value 1 -Description 'TurnOffWindowsCopilot (user)'
        # Machine policy (requires elevation; skipped gracefully if not admin).
        if (Test-GlazierAdmin) {
            Set-GlazierRegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' `
                -Name 'TurnOffWindowsCopilot' -Value 1 -Description 'TurnOffWindowsCopilot (machine)'
        } else {
            Write-GlazierLog -Level Warn -Message 'Not elevated; skipped machine-wide Copilot policy'
        }
        # Also hide the taskbar button here in case the Taskbar section is disabled.
        Set-GlazierRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' `
            -Name 'ShowCopilotButton' -Value 0 -Description 'Hide Copilot button'
    }

    if (Get-GlazierValue -Config $Config -Key 'Copilot.RemoveAppxPackage' -Default $true) {
        Write-GlazierLog -Level Step -Message 'Copilot app package'
        $packages = Get-AppxPackage -Name '*Copilot*' -ErrorAction SilentlyContinue
        if (-not $packages) {
            Write-GlazierLog -Level Skip -Message 'no Copilot Appx package present'
        } else {
            foreach ($pkg in $packages) {
                if ($script:GlazierDryRun) {
                    Write-GlazierLog -Level Change -Message "remove Appx $($pkg.Name)"
                    $script:GlazierChangeCount++
                    continue
                }
                try {
                    Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
                    Write-GlazierLog -Level Change -Message "removed Appx $($pkg.Name)"
                    $script:GlazierChangeCount++
                } catch {
                    Write-GlazierLog -Level Warn -Message "Could not remove $($pkg.Name): $($_.Exception.Message)"
                }
            }
        }
    }
}
