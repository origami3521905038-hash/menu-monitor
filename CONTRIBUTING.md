# Contributing

性能简读是一个只面向 macOS 的原生 Swift 项目。提交改动前请：

1. 使用 Xcode 26 或更高版本，并保持 Swift 6 并发检查开启。
2. 运行 `swift test`。
3. 运行 `./build.sh`，确认 arm64 与 x86_64 都能构建。
4. 对采集器改动运行 `MenuMonitorProbe`，并记录硬件相关的不可用情况。
5. 确认没有引入网络请求、网络权限、WebView 或新的常驻后台进程。

提交信息请说明行为变化、测试命令和已知的硬件限制。请不要提交
`build/`、`.build/`、`dist/` 或本机偏好数据。
