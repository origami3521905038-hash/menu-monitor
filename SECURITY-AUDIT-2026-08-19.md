# 性能简读 v1.0.1 本地安全审计

日期：2026-08-19  
范围：v1.0.1 源码、应用包、安装/卸载/打包脚本和当前本机运行副本

## 已完成检查

| 检查 | v1.0.1 结果 |
| --- | --- |
| 网络 API 静态扫描 | 通过；未发现 `URLSession`、`URLRequest`、Network.framework socket、POSIX socket 或网络依赖 |
| Info.plist 能力 | 源码元数据未声明网络、App Sandbox、App Groups 或特权 Helper；`LSUIElement=true` |
| 运行时网络句柄 | 通过；`/usr/sbin/lsof -nP -i -a -p 46484` 无输出 |
| 动态库边界 | IOReport 仅从固定 `/usr/lib/libIOReport.dylib` 加载；私有符号调用集中在 C 适配器 |
| 权限边界 | 应用无 sudo/root 采集路径；`sudo` 只可能在脚本复制/删除固定 `/Applications/MenuMonitor.app` 或系统 Installer 安装包时触发 |
| 删除路径 | `install.sh`、`uninstall.sh` 仅操作固定应用路径、精确偏好文件和精确支持目录；拒绝意外目标 |
| DMG/PKG 输出路径 | `package-dmg.sh` 和 `package-pkg.sh` 仅允许项目 `dist/` 下的目标文件，拒绝外部目录、错误扩展名和符号链接 |
| 脚本语法 | 通过：`zsh -n build.sh install.sh uninstall.sh package-dmg.sh package-pkg.sh Resources/Installer/postinstall` |
| 测试 | 通过：`swift test -c debug`，5 个测试通过 |
| 签名/架构 | 通过；应用和 UI bundle 均为 `arm64` + `x86_64`，ad-hoc deep signature 通过 |
| Gatekeeper 评估 | 未公证 ad-hoc 包被 `/usr/sbin/spctl` 拒绝属于预期；文档要求用户手动批准，不绕过系统保护 |
| 敏感材料 | 本地复核未发现 API key、密码、证书、私钥、本机偏好文件或用户特定日志 |

## 关键设计结论

- 没有 SMC 特权 Helper、守护进程、持续 root 进程或网络上报路径。
- IOReport 是私有且运行时可选的；通道、单位、计数器和范围异常会 fail closed，界面显示
  “不可用”。面板不渲染内部 `CPU + GPU SoC estimate` 来源标签，探针仍可输出该标签以便诊断。
- 安装脚本不会为数据采集申请管理员权限；`/Applications` 复制动作需要权限时才可能出现一次
  系统授权。
- DMG 内的 `MenuMonitor-Installer.pkg` 使用系统 Installer 写入固定的 `/Applications/MenuMonitor.app`
  路径；postinstall 只通过 `launchctl asuser` 以当前登录用户启动应用并注册登录项，不安装守护进程、
  不保留 root 进程。由于没有 Developer ID，PKG 本身未公证，系统可能要求用户右键“打开”。
- 告警只改变指标标题的语义色，详情不新增橙色解释区；状态栏 hover 修复使用显式空
  `toolTip` 抑制 Tahoe 的自动 help tag，不扩大权限边界。

## 外部安全扫描状态

Codex Security 原生工作区没有返回真实 `scanId`，因此本文件不声称完整威胁建模、发现、验证
或攻击路径扫描通过。当前只记录可以在本机复核的静态、运行时、权限、签名和架构检查；解锁
桌面后如需完整扫描，必须实际点击 **Start scan** 并保存返回的 scan ID。
