# GitHub Release Checklist

This checklist is for publishing `性能简读` (`MenuMonitor`) from this directory.
It describes the current local-release model: macOS 26+, universal `arm64` +
`x86_64`, ad-hoc signed, not notarized, and fully offline.

## 1. Confirm the release identity

- [ ] Read `CFBundleShortVersionString` and `CFBundleVersion` from
  `Resources/Info.plist`.
- [ ] Use the matching tag `v<CFBundleShortVersionString>` (for example,
  `v1.0.1`). Do not reuse a tag for a different build.
- [ ] Confirm the release notes do not call the app Developer ID signed,
  notarized, sandboxed, auto-updating, or a whole-machine power meter.
- [ ] Confirm the release notes distinguish the compact panel from diagnostics:
  the panel shows CPU/GPU temperatures under System Power, while the probe may
  still print the internal `CPU + GPU SoC estimate` source label.

## 2. Review the repository contents

- [ ] `README.md`, `LICENSE`, `CONTRIBUTING.md`, `SECURITY.md`, `Package.swift`,
  `Sources/`, `Resources/`, `Tests/`, and the install/build scripts are present.
- [ ] No API keys, passwords, certificates, private keys, personal logs, local
  preference files, or user-specific absolute paths are staged.
- [ ] Do not commit `build/`, `.build/`, or `dist/`; the generated DMG is a
  release attachment, not a source-tree file.
- [ ] Confirm the release notes mention the known hardware limitation: IOReport
  may be unavailable on some Apple Silicon, Intel, desktop, or future macOS
  systems, and `Unavailable` is an expected result.

## 3. Run the local verification gate

Run these commands from the project directory and keep the output with the
release record:

```zsh
swift test -c debug
./build.sh
swift run -c release MenuMonitorProbe --samples 4 --interval 2
```

- [ ] Tests pass.
- [ ] `build.sh` succeeds, including its network API audit, ad-hoc signature
  verification, and universal-architecture checks.
- [ ] The probe reports real values or explicit `Unavailable`/`Calibrating`
  states; do not replace an unavailable hardware reading with a guessed number.
- [ ] Optional install smoke test completed:

```zsh
./install.sh
./uninstall.sh
```

- [ ] The installed copy launches from `/Applications/MenuMonitor.app`, the
  login-item status reaches `enabled`, and uninstall reaches `notRegistered`.
- [ ] With the panel open, confirm all four detail strings stay on one line,
  the System Power detail shows CPU/GPU temperatures, and no `CPU + GPU SoC
  estimate` source label is rendered in the panel.
- [ ] Confirm the only colored alert text is the metric title: warning is
  orange and critical is red; no extra alert explanation row is present.
- [ ] With a full battery on external power, confirm the charging detail reads
  `Power bypass`/`旁路供电` when the conservative bypass condition is met.
- [ ] Hover the status item and confirm macOS 26 does not render the former gray
  tooltip/help rectangle; clicking the icon must still open the panel.

## 4. Build and inspect the release DMG

The script reads the artifact version from `Resources/Info.plist`. Capture that
value before packaging so the filename, checksum, and tag always agree:

```zsh
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
./package-dmg.sh "dist/MenuMonitor-${version}-universal.dmg"
```

`package-dmg.sh` rebuilds the app and validates the app bundle, deep signature,
both architectures, UDZO format, the installer package payload, and the
`/Applications` alias. The DMG includes `MenuMonitor-Installer.pkg`, which is
the recommended double-click installation path on another Mac.

- [ ] The command completes without bypassing Gatekeeper or asking for a
  collection-time administrator password.
- [ ] The artifact is a readable UDZO image containing `MenuMonitor.app`,
  `MenuMonitor-Installer.pkg`, and an `Applications` alias pointing exactly to
  `/Applications`.
- [ ] Both the app executable and UI bundle contain `arm64` and `x86_64` slices.
- [ ] Record a checksum for the exact file attached to GitHub:

```zsh
shasum -a 256 "dist/MenuMonitor-${version}-universal.dmg"
```

## 5. Commit, tag, and publish on GitHub

- [ ] Commit only the intended source and documentation changes.
- [ ] Push the branch, then create the annotated tag matching the bundle version:

```zsh
git tag -a "v${version}" -m "MenuMonitor v${version}"
git push origin main --follow-tags
```

- [ ] Open **Releases → Draft a new release**, select the tag, and attach only
  the freshly verified `MenuMonitor-<version>-universal.dmg`.
- [ ] Paste the release notes and include the SHA-256 checksum.
- [ ] State clearly that the build is ad-hoc and not notarized; on another Mac,
  macOS may require a one-time approval in **System Settings → Privacy &
  Security**.
- [ ] Publish only after the tag, source tree, asset name, version, and checksum
  all agree.

## 6. Release-notes template

```text
## MenuMonitor v<version>

### Highlights
- Offline macOS menu-bar monitor for memory, CPU, SoC power estimate, and charging power.
- Universal `arm64` + `x86_64` build for macOS 26 or later.

### Install
1. Download `MenuMonitor-<version>-universal.dmg`.
2. Open it and double-click `MenuMonitor-Installer.pkg` to install to `/Applications`;
   alternatively copy `MenuMonitor.app` manually or use `install.sh` from source.
3. On another Mac, approve the ad-hoc, not-notarized app once in Privacy & Security if macOS asks.

### Limitations
- Ad-hoc signed and not notarized; no Developer ID, App Store distribution, or automatic updates.
- The system-power number is a CPU/GPU (and optional DRAM) SoC estimate, not wall power.
  The compact panel intentionally omits the source label and uses that detail
  line for CPU/GPU temperatures; the command-line probe retains the label for
  diagnostics.
- IOReport and charging data can be unavailable on hardware or OS versions that do not expose the required fields.
- The app remains fully offline and does not upload telemetry.

### Verification
- Tests: `swift test -c debug`
- Build/package: `./build.sh`, `./package-dmg.sh`
- SHA-256: `<paste checksum here>`
```

## 7. After publishing

- [ ] Download the published asset in a clean browser session and compare its
  checksum with the release record.
- [ ] Open the DMG and confirm the app name, `MenuMonitor-Installer.pkg`, icon, and Applications alias.
- [ ] Verify the GitHub release page links to the same version shown in the app
  bundle and README.
- [ ] Keep the local verification output and checksum with the release record;
  never upload private logs or signing material.
