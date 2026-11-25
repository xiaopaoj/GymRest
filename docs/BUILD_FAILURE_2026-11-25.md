# XCTest失败分析与工作区修复 · 2026-11-25

## 用户日志证据

本次日志已实际执行45项XCTest，1项失败（其余44项通过），不是此前的编译错误或模拟器目标缺失。

失败：`ReviewRegressionTests.testFailedExerciseCommitRollsBackAndRetainsDraftValue`，原第24行比较动作数据，实际158 bytes、原151 bytes不相等。说明模拟保存失败后，当前模型仍呈现失败草稿，没有恢复已提交内容。原断言保留，不放宽、不删除、不移到修改前。

日志同时出现Application Support目录缺失、NSCocoaErrorDomain 512与sandbox提示，但后续明确写出 `Recovery attempt ... was successful!`，随后开始测试。目录日志不能被当成此次断言失败的直接根因。

工作流在test命令失败时退出65，按现有脚本不会继续执行后面的iPhoneOS Release和IPA打包步骤。不能以已执行模拟器测试推断本次生成了Release IPA。

## 修复

- 核对Apple官方 [processPendingChanges](https://developer.apple.com/documentation/swiftdata/modelcontext/processpendingchanges()) 和 [rollback](https://developer.apple.com/documentation/swiftdata/modelcontext/rollback()) 文档。同步字段修改可能仍待框架合并；回滚入口先显式处理pending changes再rollback，不调用save。
- 统一`discardPendingChanges()`，让动作编辑、计划整理、导入、历史/设置保存失败采用一致顺序，避免同类路径遗漏。
- 动作编辑保留原始Data快照；框架回滚后若现有观察对象仍保留草稿值，显式恢复原始值并整理回滚状态。始终重新抛出原保存错误，编辑器保留草稿，不伪装保存成功。
- App在初始化默认SwiftData容器前，用Foundation标准API创建缺失的Application Support父目录。保持原default.store位置，不删库、不搬库、不修改沙箱权限。
- 新增保存失败后重试/独立Context读回，以及磁盘重开后计划和历史保持不变的回归测试。原失败测试与其`context.hasChanges`断言保持有效。

## 验证状态

本地6个Python回归、shell/Python语法、YAML和Git空白检查通过。Swift语法解析相对基线无新增问题，不能代替Xcode编译。

当前共有64个XCTest，修复后尚未执行。用户提供的45项结果只证明那次运行44通过1失败，不能扩大为本工作区64项通过。按用户当前安排，修复保留工作区，未提交/推送/触发构建。


## 2026-11-25：恢复云环境后的直接验证

- 当前环境已恢复运行。实际请求 GitHub Actions 运行列表及运行 `45576462788` 完整日志均返回 HTTP 200；日志读取权限已确认，无需用户继续手动上传日志。
- 最新远程运行仍对应 `eb4329b070eb1c6dfd0de058e099802d18cb5567`，结论 failure。直接下载的日志再次确认45项测试、1项失败，失败位于 `ReviewRegressionTests.swift:24`，原始动作Data 151 bytes与失败草稿158 bytes不相等。与先前用户提供的证据一致。
- 复核工作区保留了原失败断言、失败后重试及磁盘重开测试；共64项XCTest，当前Linux环境没有Xcode，未执行iOS复验。
- 重新运行6项Python回归、shell/Python语法、HealthKit项目配置检查及Git空白检查，均通过。
- 未提交、推送或触发Actions。下一步须在授权推送后，让macOS Actions验证这批工作区修复；远程旧运行不能证明当前修复有效。
