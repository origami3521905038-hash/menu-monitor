# Plan: MenuMonitor

_Locked via grill - by Codex + user_

## Goal

Build MenuMonitor, a macOS 26+ native menu bar system monitor for the local Mac.
It must remain fully offline, use no privileged helper, stay out of the Dock,
and show memory pressure, CPU load, estimated system power, and charging power.
The build is ad-hoc signed for local installation because no Developer ID identity
is available. The app registers itself as a login item only after installation.

## Approach

1. Create an Xcode 26 Swift 6 project named `MenuMonitor`, targeting macOS 26.0
   and producing a universal `arm64` plus `x86_64` Release app. It has four targets:
   `MenuMonitorCore` for collectors, `MenuMonitor` for the accessory app,
   `MenuMonitorProbe` for command-line validation, and `MenuMonitorTests`.
   There are no third-party packages, helper targets, App Groups, entitlements,
   network libraries, or automatic signing settings.

2. Organize the project as follows:

   ```text
   MenuMonitor/
   |- MenuMonitor.xcodeproj/
   |- App/
   |  |- MenuMonitorApp.swift
   |  |- AppDelegate.swift
   |  |- StatusItemController.swift
   |  |- LoginItemController.swift
   |  `- Info.plist
   |- Metrics/
   |  |- MetricModels.swift
   |  |- MetricInterfaces.swift
   |  |- MetricsSamplingCoordinator.swift
   |  |- MemoryPressureCollector.swift
   |  |- CPULoadCollector.swift
   |  |- PowerCollector.swift
   |  |- ChargingCollector.swift
   |  `- IOReportRuntime.swift
   |- UI/
   |  |- MenuBarIconView.swift
   |  |- PopoverContentView.swift
   |  |- MetricRowView.swift
   |  |- SparklineView.swift
   |  `- PreferencesView.swift
   |- Support/
   |  |- Preferences.swift
   |  `- Formatting.swift
   |- Tools/MetricProbe/
   |  `- main.swift
   |- Tests/
   |  |- MenuMonitorTests.swift
   |  `- Fixtures/
   |- Scripts/
   |  |- build.sh
   |  |- install.sh
   |  `- uninstall.sh
   |- README.md
   `- .gitignore
   ```

3. Define strict ownership before implementing collectors. All UI-facing snapshots
   are immutable `Sendable` values. The `@MainActor @Observable` store accepts only
   those values. A single `MetricsSamplingCoordinator` actor owns every mutable
   collector, Mach allocation, Core Foundation reference, and IOReport subscription;
   none cross an actor boundary. Its one periodic task has a monotonically increasing
   generation token. Every visibility, sleep, wake, and termination transition cancels
   and awaits the old task, increments that token, and discards results that no longer
   match. AppDelegate observes `NSWorkspace.willSleepNotification` and
   `didWakeNotification`, serially suspends/reset baselines before resume, and prevents
   stale post-wake deltas from reaching the store.

   `MemoryPressureCollector` owns its `DispatchSourceMemoryPressure` on one private
   serial queue. Its event handler changes only a lock-protected pressure enum, and
   sampling reads one copied enum value; it never mutates actor-owned state directly.
   `start()` is idempotent, while sleep and termination synchronously cancel the source,
   clear its handler, and release it before the coordinator resumes or exits.

4. Use the one coordinator loop for adaptive sampling. When hidden, CPU samples every
   2 seconds and memory, power, and charging every 5 seconds. When visible, CPU and
   memory sample every second and power and charging every 2 seconds. Samples are
   timestamped with a monotonic clock and history is pruned by a 60-second time window,
   not by count. All collectors expose `calibrating`, `available`, or `unavailable`
   state rather than converting an invalid first sample into zero.

5. Implement memory pressure with an event-driven
   `DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical])`.
   Initialize to normal, process coalesced events in critical/warning/normal priority,
   and explicitly recover to normal when the source reports it. Use
   `host_statistics64` / `vm_statistics64` for displayed memory and compression.
   Fetch `host_page_size` for every collector initialization, validate that it is a
   positive bounded page size, and use checked multiplication for every
   pages-to-bytes conversion; never assume 4 KiB pages. An invalid page size or
   overflow makes the affected byte value unavailable.
   Obtain current swap use only from a separately validated `sysctlbyname("vm.swapusage")`
   `xsw_usage` query, using `xsu_used` bytes; an unavailable or malformed query yields
   an unavailable swap field. Every Mach buffer is deallocated on every return path.

6. Implement CPU load using two `host_processor_info(...,
   PROCESSOR_CPU_LOAD_INFO, ...)` samples and tick deltas for overall and per-core
   utilization, plus `getloadavg` for 1, 5, and 15 minute load averages. The first
   sample, any counter rollback, or any processor-count/layout change discards the
   complete baseline and recalibrates. Every allocated Mach buffer is released.

7. Implement power through a narrow, serialized `IOReportRuntime` adapter for the
   private `/usr/lib/libIOReport.dylib` ABI. It will:

   - load only required functions through `dlopen` / `dlsym`, fail closed if any is
     absent, and invoke no private function outside the adapter;
   - validate every returned CF object with type IDs, bounded channel count and string
     lengths, supported value ranges, and explicit unit labels; one decode anomaly
     disables the adapter for that launch rather than risking another unsafe call;
   - query `Energy Model`, create one subscription, and use a mutually exclusive,
     versioned schema of exact aggregate names. It accepts one exact CPU aggregate,
     one exact GPU aggregate, and optional exact DRAM or ANE aggregates. It rejects
     all per-core/detail channels, wildcard PCI names, duplicate aggregates, and any
     ambiguous package-plus-component combination;
   - convert only `nJ`, `uJ`, and `mJ` to joules, compute watts from cumulative-energy
     deltas and monotonic elapsed time, and discard the first sample, reset/negative
     counters, sleep transitions, unknown units, or invalid intervals.

   IOReport data is always collected first as required, but its result is exposed only
   as a `SoC component estimate`, never as a documented whole-machine meter. This
   version intentionally has no battery-registry input-power fallback: undocumented
   `SystemPowerIn` and charge fields do not provide a stable unit, scope, or synchronous
   sampling contract. The UI names the exact accepted components (for example,
   `CPU + GPU + DRAM estimate`) and returns `Unavailable` when the strict schema cannot
   be met.

8. Implement charging power with public `IOPSCopyPowerSourcesInfo` and
   `IOPSCopyPowerSourcesList` for source state, then read only `AppleSmartBattery`
   properties. Preferred instantaneous charging power is
   `ChargerData.ChargingVoltage` in mV times `ChargingCurrent` in mA divided by
   `1_000_000`. It is valid only when IOPS and `IsCharging` agree and both values are
   positive, finite, and plausible. When the confirmed state is not charging and those
   values are zero, show `0 W`; conflicting signs, units, or state are `Unavailable`.
   `InstantAmperage` is a consistency signal, not an unconditional absolute value.
   `AdapterDetails.Watts` is separately shown as rated adapter capacity, never as the
   instantaneous charging number.

   The initial IOReport schema is concrete and deliberately narrow: on macOS 26
   Apple Silicon, accept at most one `Energy Model` channel for each exact name
   `CPU Energy`, `GPU Energy`, and `DRAM Energy`; CPU and GPU are required and DRAM
   is optional. No names outside that schema, no duplicate match, and no package,
   per-core, ANE, or PCI channel is accepted. The result is labeled according to the
   accepted channel names. A future hardware or OS family needs an explicit new
   schema revision and tests; unknown layouts are unavailable rather than inferred.

9. Build the native interface around `NSStatusItem` and `NSPopover`, hosted by SwiftUI.
   `LSUIElement=true` and `.accessory` keep it out of the Dock. The compact fixed-width
   popover has one outer Liquid Glass surface using `GlassEffectContainer` and
   `.glassEffect`, SF Symbols, system fonts, semantic colors, timestamped 60-second
   Swift Charts sparklines, and a small settings window. Every metric has explicit
   available, calibrating, and unavailable text/accessibility states. The status item
   has VoiceOver labels, and the panel has Settings, About, and Quit actions. Preferences
   persist only display selections and display mode in the exact `UserDefaults` domain.

10. Register `SMAppService.mainApp` only after the app verifies it is running from the
    exact installed `/Applications/MenuMonitor.app` path. Settings exposes registration
    status and clear approval/retry guidance. The app never claims login registration
    succeeded without checking `SMAppService` status, and also supports a non-UI
    `--login-item-status` / `--unregister-login-item` command mode for scripts.
    On removal, the command requests unregistering and polls the checked status for a
    bounded interval until it reaches `notRegistered`; `uninstall.sh` treats any other
    final state as a failure and leaves the installed app intact.

11. Implement deterministic local scripts. `build.sh` resolves and validates
    `DEVELOPER_DIR`, Xcode 26+, and the macOS SDK; sets an explicit SDK and
    `ARCHS="arm64 x86_64"`; disables automatic signing; archives; ad-hoc signs only
    the built app; verifies signature with `codesign --verify --strict`; and verifies
    both slices with `lipo -archs`. `install.sh` uses fixed app name and bundle ID,
    validates all paths, quits a running prior copy, builds, copies to `/Applications`,
    verifies the copied ad-hoc signature, preserves any existing quarantine metadata,
    launches it, and checks login-item status. `uninstall.sh` validates the
    same fixed target, asks the app to unregister, waits for it to quit, and deletes
    only that app, its exact preference domain, and its exact support directory. All
    scripts fail closed on unexpected paths or statuses and install no daemon.

12. Add a `MenuMonitorProbe` command-line target with `--samples`, `--interval`, and
    `--no-ioreport` options. It prints structured collector values for comparison without
    launching UI. Inject clock, Mach, IOKit registry, IOPS, and IOReport interfaces into
    collectors; use fixtures for counter rollback, CPU-layout change, sleep reset,
    malformed CF data, unknown power units, charging sign mismatch, no battery, and
    unavailable fields. Cross-check live values against `vm_stat`, Activity Monitor,
    `top`, IOPS/battery state, and IORegistry readings with declared tolerances.

13. Define repeatable acceptance checks: hidden 10-minute mean CPU below 0.3 percent
    with CPU-time growth below 2 seconds; visible mean CPU below 1.5 percent; RSS below
    25 MB after five stable minutes; status item visible within one second of cold launch;
    bounded sampling work under its interval; no sockets in `lsof -i -a -p`; and no
    `URLSession`, socket, or networking code paths in source/dependency audits. Repeat
    hidden, visible, sleep/wake, battery/AC, dark/light, install, login-item, and
    uninstall checks. Treat unavailable power hardware as a supported result, not a pass
    for an incorrect number.

## Key Decisions & Tradeoffs

- The product is local-only and ad-hoc signed. It is not notarized or intended for
  distribution outside this Mac; Gatekeeper messaging is documented rather than
  bypassed system-wide.
- The high-precision SMC privileged helper is explicitly out of scope. The app never
  asks for collection-time administrator credentials and has no privileged code path.
- IOReport is private and runtime-optional. It provides a strictly bounded SoC-component
  estimate; direct battery telemetry can be presented only with a different, explicit
  estimate label and state validation. Ambiguous values are unavailable.
- Power never falls back to `powermetrics`, a persistent subprocess, a network service,
  or a guessed constant.
- The app is not assumed to be sandboxed as a network-control mechanism. Offline
  compliance is enforced through zero network dependencies/code paths plus static audit
  and process-scoped socket evidence at runtime.
- A single generation-safe adaptive task is preferred over multiple timers. Charts are
  time-bounded in memory and never persisted.
- `NSStatusItem` plus `NSPopover` is used rather than `MenuBarExtra` for precise popover
  lifecycle and fixed-size control while preserving SwiftUI rendering.

## Risks / Open Questions

- IOReport has no public compatibility contract. Channel names, units, or ABI may change
  across macOS releases and Apple Silicon generations; all affected paths are feature
  detected and disabled safely on anomalies.
- Intel Macs may lack usable Energy Model channels. The universal binary must compile,
  but the metric can correctly be unavailable there.
- The Xcode project can produce a universal binary on this Apple Silicon Mac, but only
  the arm64 runtime can be exercised locally.
- `/Applications` installation can require the local administrator password to copy an
  app. This is an installation action, not a data-collection permission.

## Out of Scope

- SMC helper, `powermetrics`, root daemons, and all recurring privileged work.
- Remote telemetry, analytics, update checks, cloud sync, networking, and web UI.
- App Store distribution, Developer ID notarization, or auto-updating.
- Persistent metric history, logs, or custom themes.
