# 开发进度与技术决策

## 阶段一 · 2026-11-24

已实现：AlarmKit 申请权限、30/60 秒及 1–86400 秒自定义计时、取消、系统状态/错误展示；锁屏与灵动岛 Live Activity 扩展；手动通知降级；Mock、任务替换/取消/恢复测试；macOS CI 编译/测试/未签名 IPA 打包。

任务 ID 和绝对截止时间通过 UserDefaults 保存。重新启动与前台激活时查询系统注册任务；不把本地秒数归零认定为系统已响铃。进程在注册前被终止时可能留下未注册任务记录，界面会显示系统无此任务，可以取消清除。主线程 busy 标记阻止并发注册。替换任务先取消旧任务，取消失败时不注册新任务。恢复后不重建系统闹钟。

没有增加未经核实的 AlarmKit entitlement、App Group、Critical Alerts 或后台运行模式。Info.plist 使用 NSAlarmKitUsageDescription 与 NSSupportsLiveActivities。主应用和扩展共享 AlarmMetadata 类型。SwiftData 留至阶段二。

## API 核对

已尝试访问 Apple 官方 JSON 文档，但代理返回 403；不能声称已阅读成功：
- https://developer.apple.com/documentation/alarmkit
- https://developer.apple.com/documentation/alarmkit/alarmmanager
- https://developer.apple.com/documentation/activitykit
- https://developer.apple.com/documentation/widgetkit
- https://developer.apple.com/documentation/swiftui

临时交叉核对来源（非 Apple 官方托管，最终以 CI 实际 SDK 为准）：
https://github.com/xybp888/iOS-SDKs/blob/master/iPhoneOS26.0.sdk/System/Library/Frameworks/AlarmKit.framework/Modules/AlarmKit.swiftmodule/arm64e-apple-ios.swiftinterface

核对了 AlarmManager.schedule/cancel/alarms/requestAuthorization、AlarmConfiguration.timer、AlarmPresentation、AlarmAttributes 和 AlarmPresentationState.Mode.Countdown.fireDate。文档网络访问申请仅保存草稿，未声称已经应用。

## 验证状态

Linux 无 Swift/Xcode，不能本地完成 iOS 编译。GitHub CLI 认证检查失败；未触发 Actions，未取得 IPA，未执行 XCTest，未执行真机验证。静态检查结果见最终交付说明。所有能力等待 Actions 与 SideStore 真机验收；不进入阶段二。

本地已执行并通过：`bash -n scripts/ci.sh`、`python3 -m py_compile scripts/package_ipa.py`、`git diff --cached --check`。这些仅为静态检查，不代表应用测试通过。
