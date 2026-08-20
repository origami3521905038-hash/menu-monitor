# 性能简读 v1.0.1

## Highlights

- 修复 macOS 26 菜单栏图标下方多出的灰色悬停帮助标签；状态栏标题仍可被 VoiceOver
  读取，但不再显示重复的 tooltip/help tag。
- 系统功耗面板移除 `CPU + GPU SoC estimate` 来源标签，改为在详情行显示 CPU/GPU
  温度。底层功耗仍采用保守的 CPU/GPU（设备提供时包含 DRAM）芯片估算口径；命令行
  探针继续输出来源标签，方便诊断。
- 内存、处理器、系统功耗和充电功率四项详情在中文和 English 下都保持单行，空间不足
  时收紧或尾部省略，不新增解释栏。
- 四项指标统一提供标题告警色：警告为橙色、严重为红色；详情文字保持系统语义色，
  不额外显示“正常”行。
- 充电详情在检测到外部电源、满电且适配器仍供电时显示“旁路供电”（`Power bypass`），
  仍以实际充电功率作为主值。
- 完全离线运行，无遥测、统计 SDK、WebView、网络请求或特权 SMC Helper。

## Install

1. 下载 `MenuMonitor-1.0.1-universal.dmg`。
2. 打开 DMG 后双击 `MenuMonitor-Installer.pkg`，按安装器提示安装到 `/Applications`；
   安装完成后会尝试启动菜单栏应用并注册登录项。也可以从源码执行 `./install.sh`。
3. 本版本为 ad-hoc、未公证构建，没有 Developer ID 或 Team ID。其他 Mac 首次打开时，
   macOS 可能要求在“系统设置 → 隐私与安全性”手动批准一次；若安装器被拦截，请在 Finder
   中右键选择“打开”；不要绕过 Gatekeeper。

## Limitations

- 系统功耗是标注过的 CPU/GPU（可选 DRAM）芯片估算，不是墙上功耗、充电器输入功率或
  完整的整机电表。IOReport 通道或单位不可用时，界面显示“不可用”。
- CPU/GPU 温度依赖当前机型提供的温度传感器；缺失时对应值显示 `--`，不会用猜测值替代。
- macOS 没有公开的旁路位。只有外部电源、满电、零充电电流和正的适配器功率字段同时
  满足时才显示“旁路供电”，否则保守显示“未充电”。
- 无 App Store、Developer ID、公证或自动更新发行能力。

## Verification

本版本已在同一份 v1.0.1 源码上执行以下检查：

```zsh
swift test -c debug
./build.sh
./install.sh
swift run -c release MenuMonitorProbe --samples 3 --interval 1
./package-dmg.sh "dist/MenuMonitor-1.0.1-universal.dmg"
shasum -a 256 dist/MenuMonitor-1.0.1-universal.dmg
```

同时确认 `codesign --verify --strict --deep`、无网络句柄、应用和 UI bundle 均为
`arm64` + `x86_64`，以及登录项状态为 `enabled`。未公证 ad-hoc 包被 `spctl` 拒绝是
预期结果。Codex Security 原生扫描没有 scan ID 时，只记录已完成的静态、运行时、权限和
签名检查，不得写成“完整安全扫描通过”。

- `swift test -c debug`：5 个测试通过。
- `build.sh`、`install.sh`、`package-pkg.sh` 和 `package-dmg.sh`：通过；安装副本已启动，登录项为 `enabled`。`.pkg` payload 与 DMG 内容已通过检查；本机 GUI `installer` 烟囱测试需管理员密码。
- 应用和 UI bundle：`arm64` + `x86_64`；ad-hoc deep signature 通过；运行时 `lsof -i` 无网络句柄。
- 资源采样：隐藏面板时 CPU 峰值约 `1.2%`，`footprint` 峰值 `13 MB`。
- 探针现场值：内存 `normal`、约 `7.29 GB`；CPU `9–10%`；功耗 `0.2–0.3 W`；CPU/GPU
  温度约 `35.8°C`/`30°C`；充电 `0 W`、`bypass`、适配器 `65 W`。
- 悬停验证截图 `/tmp/menumonitor-empty-tooltip-validation.png` 未显示灰色帮助标签。
- DMG：`dist/MenuMonitor-1.0.1-universal.dmg`，格式 `UDZO`。

最终 DMG SHA-256：`4bf4eb17928daa461272fe1dc0bf33683189f90533dc218a01cc14ccce194cba`
