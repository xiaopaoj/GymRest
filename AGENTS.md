# GymRest 开发规范

- 用户于2026-11-25明确调整顺序：暂缓 SideStore 验证，继续核心 App 开发；后续用户已报告部分真机安装/提醒成功，详见 docs/DEVICE_TEST_2026-11-25.md；不能扩大为全部能力通过。
- 使用现有隔离 checkout，不创建 worktree，除非用户明确要求。
- 用户于2026-11-25追加训练记录及可选健康运动匹配需求，取代最初“不保留历史/不接入Health”的限制；仍不开发重量、次数或身体分析。
- Swift 6 / SwiftUI / iOS 26+。优先 Apple 官方框架，禁用音频、定位等后台保活技巧。
- 计时业务通过 MainActor TimerService 协议隔离。系统计时负责提醒，界面刷新不能驱动提醒或自动完成训练组。
- API 先核对 Apple 官方文档及实际 Xcode SDK；无法查阅时记录来源和不确定性，禁止虚构 entitlement。
- 不保存签名凭据、Apple ID、证书或私钥。不承诺个人签名支持所有能力。
- XcodeGen project.yml 管理主应用和扩展；Bundle ID 必须保持父子关系。
- 修改后运行适用检查，更新 DEVELOPMENT.md / TESTING.md / KNOWN_ISSUES.md。未执行的编译、测试和真机验收不得写成通过。
- 不主动 push 或触发远程工作流，除非用户授权；本地 commit 可以按用户要求执行。

- 用户最新要求：开发完成后先审查和检查，保留工作区改动，等待用户再次通知才可提交、推送或触发GitHub Actions；此前推送授权不适用于后续变更。
