# Windows + SideStore 安装与续签

本仓库不需要 Apple Developer 付费会员或 App Store 分发。免费签名是否支持 AlarmKit 及扩展仍待验证。

1. 使用自己的 Apple ID，按 https://docs.sidestore.io/ 的 Windows 安装步骤安装官方要求的 Apple 驱动/设备配对工具和 SideStore。仅从官方渠道获取工具；具体 VPN/配对流程随版本变化，以官方指南为准。
2. 从 GitHub Actions 成功运行的 Artifacts 下载并解压 `GymRest-unsigned`，将 IPA 传至 iPhone 的“文件”。Artifact 不是 Release 附件。
3. 在 SideStore 的安装入口选择 `GymRest-unsigned.ipa`，使用个人账号签名。若询问是否移除扩展，为验证锁屏和灵动岛应保留 GymRestWidgets；签名失败时保留完整错误，不将移除扩展后成功视为完整验收。
4. 根据系统提示信任个人开发者并启用所需的开发者模式。启动 GymRest，单独申请 AlarmKit 权限；系统通知权限是另一个入口，仅用于降级测试。
5. 运行 TESTING.md 清单。签名失败时检查主应用 `dev.gymrest.personal` 与子扩展 `dev.gymrest.personal.widgets` 是否保持父子关系，SideStore 重写 ID 后扩展是否正确嵌入。不要通过添加猜测的 entitlement 绕过错误。
6. 免费签名通常约七天有效，按 SideStore 当前规则及时刷新。刷新依赖其指定网络/VPN/配对配置；App 自身训练计时不需要网络。续签后重复锁屏、终止进程、静音/专注和扩展测试。

切勿向仓库、Issues、CI 或聊天提交 Apple ID 密码、配对文件、私钥、证书或令牌。本项目工作流关闭签名，不接收 Apple 签名凭据。

若 AlarmKit 无法授权，先记录原始错误并取消原计时，再显式开启本地通知降级并授权。通知可能被静音、专注模式或系统策略抑制；它不能替代 AlarmKit 的全部系统能力。
