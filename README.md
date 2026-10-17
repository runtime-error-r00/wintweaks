# WinTweaks

A Windows 10/11 toolbox that keeps only what is essential and actually works: a curated app installer, a short list of tested tweaks that explain themselves, system repairs, Windows Update profiles and a Windows 11 ISO creator.

WinTweaks is based on [WinUtil](https://github.com/ChrisTitusTech/winutil) by Chris Titus Tech.

---

## Quick Start

> **WinTweaks must run as Administrator** because it changes system settings. If you start it from a normal window it asks for elevation and relaunches itself.

Open PowerShell or Terminal and run:

```ps1
irm https://github.com/runtime-error-r00/wintweaks/releases/latest/download/winutil.ps1 | iex
```

Nothing is downloaded to disk or installed: the script runs from memory.

<!-- Short link: when a domain is available, point a redirect (301/302) at the URL above,
     then replace the command with: irm https://YOUR-DOMAIN/win | iex -->

> `irm | iex` runs code from the internet. Read the source first, and to always run the same build, use a specific release instead of `latest`:
> `irm https://github.com/runtime-error-r00/wintweaks/releases/download/<tag>/winutil.ps1 | iex`

### How to open an admin terminal

- **Start menu:** Right-click Start → *Terminal (Admin)* or *Windows PowerShell (Admin)*
- **Search:** Press the `Windows key`, type `PowerShell` or `Terminal`, then `Ctrl + Shift + Enter`

---

## What's inside

| Page | What it does |
|------|--------------|
| **Install** | About 100 curated apps in 12 categories, installed with winget (Chocolatey optional). **New PC Kit** selects the essentials for a fresh install, and you can add any winget package by its ID. |
| **Tweaks** | 15 tested tweaks grouped into Privacy, System, Performance, Interface and Advanced. Each has an info icon that explains what it changes and a coloured risk dot. A System Restore point is offered once, when you press **Run Tweaks**. |
| **Config** | Windows features (WSL, Hyper-V, Sandbox...), repairs (network reset, SFC/DISM, Windows Update reset, winget reinstall), classic control panels and remote access. |
| **Updates** | Recommended profile (feature updates deferred 1 year, quality updates 4 days) or back to Windows defaults. |
| **Win11 Creator** | Build a customized Windows 11 ISO from an official image. |

Every tweak can be undone from **Undo Selected Tweaks**, except one-off actions such as Disk Cleanup.

---

## Automation / Presets

Apply a preset without the window:

```powershell
& ([ScriptBlock]::Create((irm https://github.com/runtime-error-r00/wintweaks/releases/latest/download/winutil.ps1))) -Preset Standard
```

| Preset | Description |
|--------|-------------|
| `Standard` | Recommended baseline for most PCs |
| `Minimal` | Smaller, lower-impact set |
| `Advanced` | Standard plus Windows AI removal, visual effects and the classic right-click menu |

Runs without a window always try to create a restore point before applying tweaks. See [config/preset.json](config/preset.json) for exactly what each preset selects.

---

## Publishing a release

The launch command downloads the newest **stable** GitHub release. To publish one:

1. Open **Actions** → **Release WinTweaks** → **Run workflow**.
2. Leave **pre-release** unticked.

The workflow compiles `winutil.ps1`, tags the commit with today's date (`yy.MM.dd`) and attaches the script to the release. A pre-release is skipped by `latest`; run it with [windev.ps1](windev.ps1).

---

## Build & Develop

```powershell
.\Compile.ps1        # builds winutil.ps1 from the sources
.\Compile.ps1 -Run   # builds and launches it
```

Contributor and agent rules are in [AGENTS.md](AGENTS.md); the architecture is described in [SPEC.md](SPEC.md).

---

## Credits

- [WinUtil](https://github.com/ChrisTitusTech/winutil) by Chris Titus Tech and its contributors, the base of this project.
- The tweak and app selection started from a friend's WinTweaks IT tool.

Licensed under the MIT License, see [LICENSE](LICENSE).
