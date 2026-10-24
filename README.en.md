# Menu Monitor

<p><a href="README.md"><u>简体中文</u></a> · <a href="README.en.md"><u>English</u></a> · <a href="README.ar.md"><u>العربية</u></a></p>

<div align="center">
  <img src="docs/images/hero-menu-monitor.jpg" alt="Menu Monitor macOS dashboard and menu bar panel" width="100%">
</div>

> A lightweight, native macOS menu bar monitor for system performance, temperature, and power.

[![Platform](https://img.shields.io/badge/macOS-26%2B-111827)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-6.2-f05138)](#architecture)
[![Offline](https://img.shields.io/badge/network-offline-2f7d55)](#privacy-and-local-operation)
[![Validation](https://img.shields.io/badge/build-GitHub%20Actions-2f7d55)](.github/workflows/validate.yml)
[![License](https://img.shields.io/badge/license-MIT-6f8fb3)](LICENSE)

Menu Monitor keeps essential system signals in the macOS menu bar. Click the icon to inspect memory, CPU, estimated chip power, temperature, charging power, and the last 60 seconds of trends without opening a large monitoring window or keeping another Dock icon.

## Your Mac at a glance

| Metric | Live information |
| --- | --- |
| Memory | Pressure, resident estimate, compressed memory, swap |
| CPU | Total utilization, per-core utilization, load average |
| System Power | Estimated CPU / GPU chip power and temperatures |
| Charging Power | Charging power, adapter power, power-bypass state |

The menu bar supports selectable metrics, compact and labeled modes, and Chinese / English interfaces. Metric titles use macOS semantic colors when a warning threshold is reached.

## Interface

### Live menu bar panel

<div align="center">
  <img src="docs/images/live-panel.jpg" alt="Menu Monitor live panel on macOS" width="90%">
</div>

The menu bar shows the metrics you care about. Opening the panel reveals complete values, per-core load, temperatures, power state, and a 60-second Swift Charts trend.

### Preferences

<div align="center">
  <img src="docs/images/settings.jpg" alt="Menu Monitor preferences window" width="90%">
</div>

- Select menu bar metrics.
- Switch between Compact and Labeled layouts.
- Switch Chinese / English.
- Enable or disable launch at login.

## Why it feels good

- **Native Swift 6 + SwiftUI:** a macOS-first interface built with Swift Charts.
- **Lightweight residency:** sampling slows while the panel is closed and expands when needed.
- **Fully offline:** no network requests, telemetry SDK, cloud sync, or update checks.
- **No Electron or WebView:** native app architecture with no browser runtime.
- **Local collection:** system signals come from IOKit, IOPS, and IOReport.
- **Useful detail:** per-core load, temperatures, charging power, bypass detection, and warning colors.

## Download

Open the [Latest Release](https://github.com/origami3521905038-hash/menu-monitor/releases/latest) and download the universal DMG.

1. Open the DMG.
2. Run `MenuMonitor-Installer.pkg`.
3. Follow the installer.
4. The app launches in the menu bar and attempts to register launch at login.

You can also drag `MenuMonitor.app` into Applications. That path does not register the login item automatically.

## Build from source

Requirements: macOS 26+, Xcode 26+, Swift 6.2+.

```bash
git clone https://github.com/origami3521905038-hash/menu-monitor.git
cd menu-monitor
swift test -c debug
./install.sh
```

Build without installing:

```bash
./build.sh
```

Create a DMG:

```bash
./package-dmg.sh
```

Create a package:

```bash
./package-pkg.sh
```

Uninstall:

```bash
./uninstall.sh
```

## Privacy and local operation

- Metrics are read from local system interfaces only.
- The app makes no network requests and includes no telemetry, analytics SDK, or cloud sync.
- Metric collection does not request administrator access.
- The project has no SMC helper, background daemon, or persistent root process.
- macOS may request a one-time authorization while copying the app to `/Applications`; this is unrelated to metric collection.

## Measured overhead

Test environment: macOS 26.5.2 on an 8-core Apple Silicon Mac.

| Measurement | Result |
| --- | --- |
| CPU samples with the panel closed | `0.0% / 0.8% / 0.0% / 1.2% / 0.6%` |
| Observed CPU peak | About `1.2%` |
| Peak process footprint | About `13 MB` |
| `ps` RSS | About `34–40 MB`, including shared mappings |

## Power data

System Power is an estimate derived from CPU, GPU, and available DRAM energy counters. It is not wall power, adapter input, or a full-device electricity-meter reading.

Temperature, power channels, and bypass state follow the signals available from the current Mac and macOS version.

## Architecture

```text
MenuMonitorApp      AppKit accessory app / menu bar / preferences
MenuMonitorUI       SwiftUI + Swift Charts Liquid Glass panel
MenuMonitorCore     metrics collectors and sampling coordination
CIOReportRuntime    isolated IOReport C runtime
CIOHIDTemperature   isolated IOHID temperature runtime
MenuMonitorProbe    command-line metric validation
```

## Build and repository checks

```bash
swift build -c debug
python3 Tests/validate_repo.py
```

The source includes tests for metric states, monotonic elapsed time, power states, bypass-power conditions, and value formatting; a complete Xcode toolchain can run `swift test -c debug`. GitHub Actions validates the Swift build, documentation links, and repository structure.

## Documentation

- [Project introduction](GITHUB_PROJECT_INTRO.md)
- [Release checklist](GITHUB_RELEASE_CHECKLIST.md)
- [v1.0.1 release notes](RELEASE_NOTES-v1.0.1.md)
- [Security](SECURITY.md)
- [Contributing](CONTRIBUTING.md)

## License

MIT. See [LICENSE](LICENSE).

