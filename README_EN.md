<p align="center">
  <img src="icon.png" width="128" height="128" alt="iFanControl Icon">
</p>

<h1 align="center">iFanControl</h1>

<p align="center">
  A menu bar fan control utility for Apple Silicon Macs with built-in fans
</p>

---

## Overview

iFanControl is a native macOS menu bar app for Apple Silicon Macs with controllable fans. It provides real-time temperature and RPM monitoring, automatic and manual fan control, a 5-point curve editor, in-app updates, and more robust temperature-sensor detection for supported M-series machines.

This repository now keeps only source code, scripts, and essential resources. Release archives are distributed through GitHub Releases and the official website instead of being committed into the repo.

## Features

- Menu bar display for current temperature, RPM, and control mode
- Automatic mode based on a 5-point fan curve
- Manual mode with a fixed RPM target
- Fan curve editor with normal/reversed Y-axis display options
- Safety floor RPM at critical temperature without overriding higher user RPM
- Temperature source selection with automatic hottest-sensor mode by default, plus separate CPU/GPU average-temperature and manual sensor modes
- In-app updates with manual and scheduled checks
- Unified “About iFanControl” window with version, update controls, GitHub, and restart
- Anonymous user-count stats sent at a fixed interval, configurable in About / Help
- Launch at login
- Install diagnostics and uninstall scripts

## Supported Scope

- macOS 26 or later
- Apple Silicon Macs with built-in fans
- The developer only has a Mac mini M4, used reliably for months. Other models may work in theory but require an actual trial.

Note: fanless devices will not expose controllable fan hardware. Temperature sources shown in the UI are thermal sensors exposed by the system and do not necessarily map one-to-one to CPU or GPU core counts.

## Installation

Download the PKG from [GitHub Releases](https://github.com/PureMilkchun/iFanControl/releases) or the [official website](https://ifancontrol.puremilkchun.top).

1. Quit iFanControl from the menu bar, then double-click the installer.
2. Follow the macOS installation steps. Existing settings are preserved.
3. Open iFanControl from Applications. If macOS blocks it, go to System Settings → Privacy & Security, click Open Anyway, then confirm Open.

Older versions continue to receive ZIP updates through the existing in-app updater. For a manual ZIP installation, unzip the archive, drag `install.sh` into Terminal, and press Return.

## Usage

1. Open `/Applications/iFanControl.app`
2. The app lives in the menu bar
3. Use the menu to switch auto/manual mode, edit the fan curve, and adjust the safety floor RPM
4. Open `About iFanControl...` to view version info, check for updates, toggle automatic update checks, toggle anonymous stats, restart the app, or open GitHub

## Privacy & Stats

iFanControl sends periodic anonymous user-count stats by default to improve product quality and stability. It only includes a random anonymous ID, version, and build; it does not send your name, email, serial number, device name, fan readings, or temperature readings. You can disable this in `About / Help -> Overview` by turning off “Anonymous user-count stats”.

## Repository Layout

```text
.
├── Package.swift
├── Sources/
│   ├── FanCurveEditor/
│   └── MacFanControl/
├── iFanControl.app/
├── install.sh
├── diagnose.sh
├── uninstall.sh
├── Install.command
├── 安装说明.html
└── icon.png
```

## Development

```bash
swift build
swift run
```

CI is defined in `.github/workflows/swift.yml`.

## Update Flow

- Manual check: `About iFanControl... -> Check for Updates`
- Automatic check: delayed on launch; when enabled, it fetches the manifest directly so new releases are not missed
- Update source: `pages.dev` manifest and ZIP
- Failure fallback: open GitHub Releases for manual download

## Uninstall

```bash
./uninstall.sh
```

If the script came from a downloaded ZIP, drag `uninstall.sh` into Terminal and run it there; do not rely on double-clicking `.command` files.

## Credits

- [kentsmc](https://github.com/exelban/kentsmc)
- [Stats](https://github.com/exelban/stats)

## License

[MIT](LICENSE)
