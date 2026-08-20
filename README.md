# 性能简读

性能简读是一个原生 macOS 26 菜单栏监控工具，提供四项本地指标：

- 内存压力、驻留内存估算、压缩内存和当前交换内存
- 总体处理器利用率、逐核利用率和负载平均值
- Mac 支持时提供保守的 CPU + GPU 芯片功耗估算；面板详情行同时显示 CPU/GPU 温度
- 已确认的电池充电功率和适配器额定功率
- 设置中可切换中文/English、选择菜单栏指标和显示模式；指标告警只改变标题语义色

它以 accessory 应用运行，只显示在菜单栏，不显示 Dock 图标。

## v1.0.1 界面修复

- 系统功耗面板不再显示 `CPU + GPU SoC estimate` 来源标签；功耗数值仍保持
  保守的芯片估算口径，来源名称继续保留在命令行探针中供诊断使用。
- 四项指标的中文和 English 详情均限制为单行；空间不足时使用收紧字距和尾部省略，
  不改变数值或新增解释区。
- 系统功耗详情行显示 `CPU …°C·GPU …°C`；指标标题在达到阈值时才使用橙色或红色，
  其他文字保持系统语义色。“正常”不再作为内存详情文本显示。
- 电池已满、接入外部电源且检测到适配器旁路时，充电功率下方的小字显示“旁路供电”
  （English 为 `Power bypass`），主值仍显示实际充电功率。
- 修复 macOS 26 菜单栏图标下方多出的灰色悬停帮助标签；状态栏标题仍可被 VoiceOver
  读取，但不会再把实时标题合成为可见 tooltip。

## 环境要求

- macOS 26（Tahoe）或更高版本
- Xcode 26 或更高版本
- 当前账户可以写入 `/Applications`，或只在复制应用时批准一次系统管理员提示

本地构建不需要 Developer ID 或 Team ID。应用使用 ad-hoc 签名，不做公证。

## 安装

在项目目录执行：

```zsh
./install.sh
```

脚本会构建 arm64 + x86_64 通用应用，验证 ad-hoc 签名，安装到
`/Applications/MenuMonitor.app`，启动应用，并确认登录项已启用。若系统保护
`/Applications`，只会在复制应用时请求一次管理员授权，与指标采集无关。

在其他 Mac 上首次打开 ad-hoc、未公证应用时，Gatekeeper 可能要求在“系统设置”
中手动批准一次。脚本不会关闭或绕过 Gatekeeper，也不会移除已有隔离标记。

只构建不安装：

```zsh
./build.sh
```

构建结果位于 `build/MenuMonitor.app`。

生成可分发的本地 DMG（仍为 ad-hoc、未公证）：

```zsh
./package-dmg.sh
```

只生成安装器包：

```zsh
./package-pkg.sh
```

默认输出位于 `dist/MenuMonitor-<版本>-universal.dmg`（版本号由
`Resources/Info.plist` 自动读取；也可以把 `dist/` 下的目标文件名作为 `package-dmg.sh` 的第一个参数传入）。镜像中同时包含
`MenuMonitor-Installer.pkg`、应用本体和指向 `/Applications` 的快捷方式。
在其他 Mac 上双击 `MenuMonitor-Installer.pkg`，按安装器提示完成安装；安装完成后会尝试以当前登录用户启动菜单栏应用并注册开机自启。
也可以直接把应用拖入“应用程序”，但这种方式不会自动注册登录项。
由于当前没有 Developer ID，安装器包本身也未公证；若系统拦截安装器，请在 Finder 中右键
`MenuMonitor-Installer.pkg` 选择“打开”，再按 macOS 提示确认一次。

维护者发布源码和 DMG 时，请按仓库内的
[`GITHUB_RELEASE_CHECKLIST.md`](GITHUB_RELEASE_CHECKLIST.md) 逐项复核版本号、签名、架构、校验值和发布说明。

卸载：

```zsh
./uninstall.sh
```

卸载会先确认登录项已变为 `notRegistered`，然后只删除
`/Applications/MenuMonitor.app`、`com.local.menumonitor` 偏好文件和应用的
精确支持目录（如果存在）。

## Privacy and Permissions

性能简读完全离线运行，不做数据上报，不包含统计 SDK、云同步、更新检查、WebView
或网络能力。它没有特权 Helper、守护进程、root 采集路径，也不访问 SMC。

默认采集器只使用本地 Darwin、AppKit、IOKit、IOPS 和运行时检查的 IOReport
适配器。采集过程中不会弹出密码框。

## 指标口径

### Memory pressure

内存压力由事件驱动。显示的内存使用主机实际 VM 页大小，因此 Apple Silicon
的 16 KiB 页不会被误当成 4 KiB。驻留估算包含活跃页、不可清除的非活跃页、
wired 页和压缩页；当前交换内存来自 `vm.swapusage`。

### CPU load

处理器利用率由连续的 `host_processor_info` tick 样本计算。首次采样、计数器
回退、处理器拓扑变化或唤醒后会重新校准，不会显示臆造的零值。

### System power

系统功耗采用保守口径。它通过私有 IOReport 运行时读取精确的 `Energy Model`
聚合名称：`CPU Energy`、`GPU Energy`，以及设备提供时的 `DRAM Energy`。当前
Mac 可能只提供 CPU + GPU；每个累计计数器按自身单位归一化，再通过单调时间差
计算功率。

结果的内部来源标记为“芯片估算”，不会冒充墙上功耗、充电器输入功率或有文档保证的整机电表。
为保持面板紧凑，面板只显示功耗数值和 CPU/GPU 温度；命令行探针仍会输出来源标记。
未知通道布局、重复通道、错误单位、计数器重置或异常数据都会显示“不可用”。

### Charging power

充电功率仅在公共 IOPS 状态与 `AppleSmartBattery` 状态都确认充电时，按
`ChargingVoltage`（mV）乘 `ChargingCurrent`（mA）再除以一百万计算。适配器
功率只显示额定容量；达到充电上限且电流为零时，正确显示 `0 W`。当系统同时
确认外部电源已连接、电池已满、电池充电电流为零，并且
`BatteryData.AdapterPower` 仍为正值时，小字会标注“旁路供电”。macOS 没有公开
旁路位，因此缺少任一字段时保守显示“未充电”，不会把普通充电上限状态误报为旁路。

## Interface and Performance Design

状态栏使用 AppKit，以保持隐藏采集进程轻量。Liquid Glass SwiftUI 面板和 Swift Charts
折线图放在独立 bundle 中，仅在打开面板或设置窗口时加载，关闭后释放。状态栏弹出框
关闭额外动画并预先确定内容尺寸，因此不会叠加不必要的等待。隐藏进程不直接链接该
UI bundle 或 Charts；macOS 仍可能把共享的 `SwiftUICore` 代码映射到进程中。

隐藏时处理器每 5 秒采样一次，内存和充电每 15 秒一次，IOReport 功耗每 30 秒一次。
打开面板后处理器和内存提升到每 1 秒，功耗和充电提升到每 2 秒。历史数据带时间戳，
只在可视界面打开时保留最近 60 秒。

告警只作用于对应指标标题：内存压力、处理器利用率、功耗/温度或充电负载达到保守阈值时，
标题按严重程度使用橙色或红色；详情文字不会新增告警栏，也不会用橙色取代系统语义色。

## 目录结构

```text
Sources/MenuMonitorCore/    采集器、模型和采样协调器
Sources/CIOReportRuntime/   隔离的私有 IOReport C 运行时适配器
Sources/MenuMonitorApp/     AppKit accessory 应用、状态栏和安装行为
Sources/MenuMonitorUI/      可按需加载的 SwiftUI Liquid Glass 界面 bundle
Sources/MenuMonitorProbe/   命令行采集验证工具
Tests/                      模型与采集器行为测试
Resources/                  应用和 UI bundle 元数据
```

## 已知限制

- IOReport 是私有且依赖硬件的接口，未来 macOS、Intel Mac、台式机或部分
  Apple Silicon 机型可能无法提供数据；此时显示“不可用”是受支持的安全结果。
- 芯片估算不包含显示屏、存储、无线电、充电损耗及未被接受通道覆盖的组件。
- 本版本采用 ad-hoc 签名，不是 App Store、Developer ID、公证或自动更新发行版；
  本机可直接安装，其他 Mac 首次打开可能需要在“系统设置 → 隐私与安全性”手动批准。
- 登录项注册有意限制为从 `/Applications/MenuMonitor.app` 安装副本执行。
