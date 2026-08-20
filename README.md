# 为什么是性能简读

市面上不少系统监控类应用要么本身就很「重」，要么需要联网上报数据，要么安装时索要常驻的管理员权限。性能简读反其道而行：用原生 Swift 6 直接调用 IOKit / IOReport 读取系统接口，不使用 Electron、不使用 WebView；应用是不占 Dock 的 accessory 程序，完全离线运行，采集过程不请求管理员权限，也没有常驻的守护进程。

点击菜单栏图标展开性能简读面板，查看四类指标的实时数值，以及最近 60 秒的变化趋势：

- 内存压力、驻留内存估算、压缩内存和当前交换内存
- 总体处理器利用率、逐核利用率和负载平均值
- Mac 支持时提供保守的 CPU + GPU 芯片功耗估算；面板详情行同时显示 CPU/GPU 温度
- 已确认的电池充电功率和适配器额定功率
- 设置中可切换中文/English、选择菜单栏指标和显示模式；指标告警会改变标题语义色

## 隐私与安全边界

网络请求：无——源码静态扫描与运行时网络句柄检查均不包含网络路径
遥测 / 统计 SDK：无
云同步 / 自动更新检查：无，也没有网络服务端
数据采集范围：仅本机系统接口（IOKit、IOPS、IOReport）
管理员权限：采集本身不请求；复制到 /Applications 时可能出现一次系统授权，与读取指标无关
常驻进程：无 SMC Helper、无守护进程、无持续 root 进程

## 实测性能

监控工具本身的开销，往往是用户最先关心的问题。以下数据来自验收测试环境，供参考。
测试环境：macOS 26.5.2 · Apple Silicon 八核

CPU 占用（面板关闭，5 次采样）	0.0% / 0.8% / 0.0% / 1.2% / 0.6%
本轮观测 CPU 峰值	约 1.2%
进程 footprint 峰值	约 13 MB
ps 报告的 RSS	约 34–40 MB（含共享映射，不能直接等同于私有内存）

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

## 数据口径与责任声明

•系统功耗是基于 CPU、GPU 及（设备提供时）DRAM 能量计数推导出的保守芯片估算，不等同于墙上功耗、适配器输入功率或整机电表读数，也不覆盖显示屏、存储、无线电和充电损耗。
•部分机型、系统版本或硬件状态可能不提供 IOReport 或温度通道，此时显示「不可用」属于预期行为，而非软件缺陷。
•充电功率仅在公共电源状态与电池注册表状态相互确认后才会计算并显示。
•「旁路供电」仅在外接电源、电池满电、零充电电流、正适配器功率四个条件同时成立时才会显示。

## 适用场景

适合————个人日常观察系统状态、性能排障、开发调试参考、了解功耗与温度变化趋势
不适合————安全关键控制场景、设备保护机制、能耗计费、性能认证

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
