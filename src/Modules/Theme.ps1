# =============================================================================
# Theme.ps1 - dark mode and solid black desktop background
# =============================================================================

Set-StrictMode -Version Latest

$script:ThemePersonalize = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize'

# P/Invoke for applying wallpaper/colour changes live. Loaded lazily; harmless if
# the type already exists on a repeat run.
function Add-GlazierNativeInterop {
    if (-not ('Glazier.NativeMethods' -as [type])) {
        Add-Type -Namespace 'Glazier' -Name 'NativeMethods' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Auto)]
public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);

[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Auto)]
public static extern System.IntPtr SendMessageTimeout(System.IntPtr hWnd, int Msg, System.IntPtr wParam, string lParam, int fuFlags, int uTimeout, out System.IntPtr lpdwResult);
'@
    }
}

function Set-GlazierSolidBackground {
    Write-GlazierLog -Level Step -Message 'Solid black background'

    # Personalisation "Background = Solid color, black".
    $before = $script:GlazierChangeCount
    Set-GlazierRegistryValue -Path 'HKCU:\Control Panel\Colors' -Name 'Background' `
        -Value '0 0 0' -Type String -Description 'Desktop background colour (black)'
    Set-GlazierRegistryValue -Path 'HKCU:\Control Panel\Desktop' -Name 'WallPaper' `
        -Value '' -Type String -Description 'Clear wallpaper image'
    # 10 = solid colour fill (no picture).
    Set-GlazierRegistryValue -Path 'HKCU:\Control Panel\Desktop' -Name 'WallpaperStyle' `
        -Value '10' -Type String -Description 'Wallpaper style (fill)'

    if ($script:GlazierDryRun -or ($script:GlazierChangeCount -eq $before)) { return }

    try {
        Add-GlazierNativeInterop
        # SPI_SETDESKWALLPAPER = 20; SPIF_UPDATEINIFILE (1) | SPIF_SENDWININICHANGE (2).
        [void][Glazier.NativeMethods]::SystemParametersInfo(20, 0, '', 3)
        Write-GlazierLog -Level Info -Message 'Applied blank wallpaper live.'
    } catch {
        Write-GlazierLog -Level Warn -Message "Background applied in registry; live refresh failed: $($_.Exception.Message)"
    }
}

function Update-GlazierImmersiveColor {
    if ($script:GlazierDryRun) { return }
    try {
        Add-GlazierNativeInterop
        # Broadcast WM_SETTINGCHANGE so the shell re-reads the theme without a logoff.
        $HWND_BROADCAST = [IntPtr]0xffff
        $WM_SETTINGCHANGE = 0x001A
        $result = [IntPtr]::Zero
        [void][Glazier.NativeMethods]::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE, [IntPtr]::Zero, 'ImmersiveColorSet', 2, 1000, [ref]$result)
    } catch {
        Write-GlazierLog -Level Warn -Message "Could not broadcast theme change: $($_.Exception.Message)"
    }
}

function Invoke-GlazierTheme {
    param([Parameter(Mandatory)]$Config)

    Write-GlazierSection 'Theme & Appearance'

    if (-not (Test-GlazierEnabled -Config $Config -Key 'Theme')) {
        Write-GlazierLog -Level Skip -Message 'Theme section disabled'
        return
    }

    $mode = [string](Get-GlazierValue -Config $Config -Key 'Theme.Mode' -Default 'Dark')
    $lightValue = if ($mode -ieq 'Dark') { 0 } else { 1 }
    $before = $script:GlazierChangeCount
    Set-GlazierRegistryValue -Path $script:ThemePersonalize -Name 'AppsUseLightTheme' `
        -Value $lightValue -Description "Apps theme ($mode)"
    Set-GlazierRegistryValue -Path $script:ThemePersonalize -Name 'SystemUsesLightTheme' `
        -Value $lightValue -Description "System theme ($mode)"
    if ($script:GlazierChangeCount -ne $before) { Update-GlazierImmersiveColor }

    $background = [string](Get-GlazierValue -Config $Config -Key 'Theme.Background' -Default 'None')
    if ($background -ieq 'SolidBlack') {
        Set-GlazierSolidBackground
    }
}
