# Glazier

Idempotent Windows 11 provisioning, driven by a single YAML file. Glazier
replicates an ideal Windows environment across machines: applications, Windows
features, taskbar and Explorer tweaks, default apps, theme, network shares and
.NET tooling — all toggled with feature flags and safe to re-run.

## Tenets

- **One config file.** Everything is a feature flag in [`glazier.yaml`](glazier.yaml).
- **Idempotent.** Every step checks current state and only changes what's missing.
- **WinGet-first.** Applications install via WinGet.
- **MIT licensed.** See [LICENSE](LICENSE).

## Requirements

- Windows 11
- WinGet ("App Installer" from the Microsoft Store) — pre-installed on current Windows 11
- Windows PowerShell 5.1 or PowerShell 7+ (Glazier auto-installs the `powershell-yaml`
  module on first run)
- Administrator rights (Glazier self-elevates)

## Quick start

```powershell
# From an elevated or normal PowerShell prompt:
.\Install.ps1

# Preview everything without changing the system:
.\Install.ps1 -DryRun

# Run only specific sections:
.\Install.ps1 -Only Applications,DotNet,Theme
```

Glazier self-elevates via UAC. To avoid elevation (admin-only sections are then
skipped with a warning), pass `-NoElevate`.

### Using your own config

Keep the committed `glazier.yaml` as the template and copy it for local use —
`glazier.local.yaml` is gitignored:

```powershell
Copy-Item .\glazier.yaml .\glazier.local.yaml
.\Install.ps1 -ConfigPath .\glazier.local.yaml
```

## What it configures

Every section below is a flag in `glazier.yaml`; set `Enabled: false` to skip it.

| Section | What it does |
| --- | --- |
| `Applications` | Installs apps via WinGet (Fork, Docker Desktop, OBS, Rider, Firefox, Bitwarden, Zed, Discord, PowerToys, PowerShell 7, VS Code, DB Browser for SQLite, WinSCP, x64dbg, VLC, NanaZip, HxD, ShareX), gaming redistributables (DirectX + VC++ runtimes), and the NVIDIA App when an NVIDIA GPU is detected. |
| `WindowsFeatures` | Enables Windows Sandbox, Remote Desktop (+ firewall/NLA), and the OpenSSH Server (installed, set to auto-start, firewall opened). |
| `Taskbar` | Left alignment, removes Search / Task View / Widgets / Copilot buttons, and pins Explorer, Bitwarden, Fork, Discord, Zed. |
| `Explorer` | Shows hidden files, protected OS (system) files and file extensions; pins your home folder to Quick Access. |
| `Copilot` | Disables Windows Copilot via policy and removes the Copilot app package. |
| `Defaults` | Sets Firefox as the default browser, makes NanaZip the default for archive types, and sets PowerShell 7 as the Windows Terminal default profile. |
| `Theme` | Dark mode + solid black desktop background. |
| `NetworkShares` | Mounts SMB shares (e.g. `\\server\Data`), prompting for the password at runtime. |
| `DotNet` | Installs the .NET SDKs you list (11, 10, 9 by default) and the global `dotnet-ef` tool. |
| `Fork` | Resolves the repository home (`D:\Repositories` if `D:` exists, else `C:\Repositories`), creates it, and writes Fork's default-repository setting. |

## Idempotency

Re-running Glazier is safe and expected. WinGet installs are skipped when the
package is already present; registry values are written only when they differ;
features, services, shares and pins are checked before acting. A `-DryRun` shows
exactly what a real run would change.

## Windows limitations (and how Glazier handles them)

Some of these tasks are deliberately restricted by Windows. Glazier uses the
best available method and flags where a sign-in or one-time app launch is needed:

- **Default browser & archive associations.** Windows 11 protects the default-apps
  choice with a per-user hash that scripts cannot write directly. Glazier uses
  [SetUserFTA](https://kolbi.cz/) (a small third-party helper) to set them. The
  download is opt-in via `Defaults.UseSetUserFTA` and is cached in `tools/`.
- **NanaZip archive types.** NanaZip registers its file-type ProgIds the first
  time it runs. Launch NanaZip once before setting it as default, or Glazier will
  warn and skip extensions it can't resolve (safe to re-run afterward).
- **Taskbar pins.** Declared in a per-user `LayoutModification.xml`; Windows 11
  applies these at your **next sign-in**, not live.
- **Quick Access ordering.** Glazier pins your home folder, but Windows exposes no
  API to force its position — drag it to the top once if you want it first.
- **Windows Terminal default profile.** Requires Terminal to have been launched
  once (so `settings.json` exists). Glazier warns if it isn't there yet.
- **Windows Sandbox / OpenSSH.** May require a reboot to finish enabling.

## Project layout

```
Glazier/
  Install.ps1          # entry point: self-elevates, bootstraps, orchestrates
  glazier.yaml         # the single configuration file (feature flags)
  src/
    Common.ps1         # logging, idempotent registry/state helpers
    Config.ps1         # YAML loading + safe accessors
    Modules/           # one module per concern (Applications, Theme, ...)
  tools/               # downloaded helpers (e.g. SetUserFTA), gitignored
```

## License

MIT — see [LICENSE](LICENSE).
