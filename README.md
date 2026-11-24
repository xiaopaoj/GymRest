# GymRest

个人原生 iOS 26+ 健身休息计时器。当前仅实现**阶段一技术验证**，尚无训练计划或训练历史功能。

SwiftUI + AlarmKit，独立 WidgetKit Live Activity 扩展；无账号、后端或第三方运行时依赖。提供显式可选的 UserNotifications 降级模式，其无法保证突破静音和专注模式，也不提供 AlarmKit 锁屏倒计时。

## 使用

1. 将本仓库代码推送至 GitHub `main`，或在 Actions 中选择 **iOS 26 validation and unsigned IPA → Run workflow**。
2. 工作流在 `macos-26` 检查并选择已安装且带 iOS 26 SDK 的 Xcode；缺少 SDK/模拟器时明确失败。
3. 下载 `GymRest-unsigned` Artifact 并解压得到 `GymRest-unsigned.ipa`。这不是已签名的可直接安装应用。
4. 按 [SideStore 指南](docs/SIDESTORE.md) 签名安装，在 App 内申请 AlarmKit 权限，测试 30 秒、60 秒、自定义秒数及取消。
5. 按 [TESTING.md](TESTING.md) 填写真机结果。阶段一通过前不进入完整业务开发。

## 开发

macOS + Xcode 26（iOS 26 SDK）+ XcodeGen，执行 `bash scripts/ci.sh`。Swift 6，最低 iOS 26.0。`project.yml` 是工程唯一来源，生成的 Xcode 工程和构建目录不入库。

Linux / Windows 无法编译 Apple SDK；此处源码生成和静态检查不代表 iOS 编译通过。构建日志及 XCTest `.xcresult` 上传至 `GymRest-diagnostics`。免费签名和 AlarmKit 能力未获真机确认；见 [已知限制](KNOWN_ISSUES.md)。
