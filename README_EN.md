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
- Safety floor RPM at critical temperature without overriding higher user RPM
- Temperature source selection with automatic hottest-sensor mode by default
- In-app updates with manual and scheduled checks
- Unified “About iFanControl” window with version, update controls, GitHub, and restart
- Anonymous active-use stats, sent at most once per day and configurable in About / Help
- Launch at login
- Install diagnostics and uninstall scripts

## Supported Scope

- macOS 13 or later
- Apple Silicon Macs with built-in fans
- Primarily tested for M1 / M2 / M3 / M4 devices

Note: fanless devices will not expose controllable fan hardware. Temperature sources shown in the UI are thermal sensors exposed by the system and do not necessarily map one-to-one to CPU or GPU core counts.

## Installation

### From GitHub Releases

Download the latest ZIP from [Releases](https://github.com/PureMilkchun/iFanControl/releases), unzip it, then run:

```bash
cd ~/Downloads/iFanControl-* && ./install.sh
```

Recommended method: open Terminal, drag `install.sh` into the window, then press Enter.  
Note: after downloading from the internet, `.command` files may be repeatedly blocked by macOS, so do not rely on double-clicking `.command` for installation.

### From the official website

- Website: [ifancontrol.puremilkchun.top](https://ifancontrol.puremilkchun.top)
- Update manifest: [ifan-59w.pages.dev](https://ifan-59w.pages.dev/update-manifest.json)

You can also open [安装说明.html](安装说明.html) for the illustrated install guide.

## Usage

1. Open `/Applications/iFanControl.app`
2. The app lives in the menu bar
3. Use the menu to switch auto/manual mode, edit the fan curve, and adjust the safety floor RPM
4. Open `About iFanControl...` to view version info, check for updates, toggle automatic update checks, toggle anonymous stats, restart the app, or open GitHub

## Privacy & Stats

iFanControl sends an anonymous active-use heartbeat at most once per day by default, so the solo developer can understand whether the app is still being used in the real world. It only includes a random anonymous ID, version, and build; it does not send your name, email, serial number, device name, fan readings, or temperature readings. You can disable this in `About / Help -> Overview` by turning off “Share anonymous active-use statistics”.

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
