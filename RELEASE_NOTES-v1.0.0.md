# 性能简读 v1.0.0

## Highlights

- 原生 macOS 26 菜单栏监控：内存压力、CPU、芯片功耗估算和充电功率。
- 中文/English 设置切换，可选择菜单栏指标和紧凑/带标签显示模式。
- Liquid Glass 面板、60 秒折线图、CPU/GPU 温度和旁路供电说明。
- 完全离线运行，无遥测、统计 SDK、WebView 或网络请求。
- `arm64` + `x86_64` 通用构建。

## Install

1. 下载 `MenuMonitor-1.0.0-universal.dmg`。
2. 打开镜像，将 `MenuMonitor.app` 拖到 `/Applications`，或从源码执行 `./install.sh`。
3. 这是 ad-hoc、未公证应用。其他 Mac 首次打开时，macOS 可能要求在“系统设置 → 隐私与安全性”手动批准一次。

## Limitations

- 系统功耗是标注过的 CPU/GPU（设备提供时包含 DRAM）芯片估算，不是墙上功耗或充电器输入功率。
- IOReport 和充电字段依赖硬件与系统版本，无法读取时显示“不可用”。
- 无 Developer ID、App Store、公证或自动更新。

## Verification

- Tests: `swift test -c debug`（5 tests）
- Build/package: `./build.sh`, `./package-dmg.sh dist/MenuMonitor-1.0.0-universal.dmg`
- SHA-256: `79dc473a71e98e0bd2a890cfe0fe0dccacae009f9b1ff4adb7f029f5427a512f`
