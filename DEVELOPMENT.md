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

## 核心开发 · 2026-11-25

用户明确调整优先级：暂不关注 SideStore，继续 App 开发；这取代了此前等待阶段一真机通过的开发门槛，没有把待验证项改为通过。

新增 SwiftData 计划、偏好和唯一活动训练记录。计划将按顺序排列的 Codable 动作值保存为 Data，动作 ID、独立休息和末组开关完整保留。偏好记录同时作为首次初始化标识，删除全部计划后不重复创建默认计划。

训练状态机包含 idle/training/resting/paused/completed。执行状态使用不可变计划快照和每动作完成计数，手动完成组后才启动休息。默认最后一组无休息；用户启用后包括最后一个动作末组的休息也执行。completed 只用于当前完成界面，持久化活动记录立即清除，不保留历史。

暂停采用“先取消系统任务，再保存剩余秒数”；继续、重启和调时均重新注册，保证不会留下旧闹钟。注册前持久化任务 ID，注册成功后再标记有效；失败后保留已手动完成的组数，可重试/跳过。取消失败阻止导航、结束和重新注册。恢复仅查询系统，不重新注册；AlarmKit 通过系统状态及 ActivityKit 内容校准，通知通过 pending trigger 校准。

新增计划列表、编辑页、执行页、设置页及数据打开失败页面。独立提醒测试仅在无当前训练时可进入；开始训练会清理技术验证模式遗留任务。SwiftData 存储不包含云同步配置。JSON 导入导出、指定组休息覆盖留待后续。

新增 11 个训练测试，覆盖初始化、删除后不重建、空计划、动作独立休息、手动组数、默认末组跳转、末组休息开关、重复点击、暂停调时、完成清理、注册失败重试、取消失败、恢复校准、任务异常消失及快照隔离（部分合并为同一测试方法）。现有 3 个 Probe 测试保留。

本轮验证：shell/Python 语法、项目 YAML 读取、Git 空白检查通过。新增 Swift 文件通过 tree-sitter 语法解析；解析器对两个原有文件的语法已有不兼容报错，不能视为 Swift 编译结果。Linux 未执行新增 XCTest 或 iOS 编译。此前上传 IPA 的结构检查不能证明本轮代码通过构建。GitHub API 当前返回403，尚未取得本轮远程测试结果。

## 编译修复 · 2026-11-25

用户提供的 Xcode 26.0.1 日志确认 LibraryView 复制计划的 catch 分支将字符串赋给隐式捕获的只读 Error，导致编译失败（exit 65），测试因此取消。已改为 self.error，明确更新页面错误状态。检查了全部 catch 分支，没有发现其他同类赋值。修复后尚未取得新的 Xcode 构建或 XCTest 结果。

## 真机反馈归档 · 2026-11-25（Asia/Shanghai）

根据用户跨聊天转交的实测结果新增 [真机记录](docs/DEVICE_TEST_2026-11-25.md)，分别记录包结构检查、安装/启动、10秒前台/锁屏/后台提醒及30秒提醒成功。保留首次操作无反应的问题，未归因或标为修复；扩展注册、Live Activities、续签和 XCTest 均未据此标为通过。产物未绑定 commit/设备/iOS版本，本次只更新文档，没有重新测试或改变功能。

## 功能补齐、训练记录与 CI 修复 · 2026-11-25

用户补充：原“图表”指 App 图标；同时要求训练记录和 Apple Watch 运动记录匹配。这取代原不保留历史/不接入Health的限制，不扩展至重量、次数、热量统计或身体分析。

- 计划JSON导入导出：version 1，全量字段/UUID/范围校验，先确认后追加，生成新ID，不覆盖当前训练；单次文件上限10MB，不限制库中计划/动作数量。
- 动作按组休息覆盖位于折叠高级区，默认流程不增加字段。旧动作无覆盖字段可兼容解码，训练按刚完成组号取覆盖值。临时调整不会回写预设。
- 训练记录保存开始/结束、计划快照、逐动作完成组数、完成/提前结束；与活动状态删除同次保存，按session ID防重复归档。旧活动无开始时间时不猜测，不提供匹配。
- 只读HealthKit：明确操作后授权，只查询workout，按时间重合排序、用户确认关联，不写健康数据，不读取心率。默认CI编译健康分支；手动取消healthkit可生成无能力版本。官方能力表HealthKit在Apple Developer列支持，不能假定必须付费；SideStore保留entitlement及实际数据访问仍待验证。已阅读官方授权文档、能力表及HealthKit entitlement文档，详见 docs/HEALTHKIT.md。
- 锁屏/灵动岛增加动作、已完成组数及下一步，倒计时依赖系统state/fireDate。通过共享中立RestContext传递业务信息；深链只打开当前训练。通知降级不宣称有灵动岛能力。暂停仍采用取消，暂停期间实时活动可能消失。
- 生成全新橙色哑铃/计时圆环图标，原图为1254 RGB不透明PNG；CI用macOS sips生成1024 App Icon资源，不改原图，不使用付费SDK。
- 首次未决定权限时，计时服务主动申请权限；拒绝仍展示错误。此改进不代表已找到或修复用户此前“首次操作无反应”的根因。

用户提供的exit70日志发生于测试启动之前：simctl可用的设备并未被所选Xcode/scheme认可；迁移日志本身不能证明启动失败。CI改用runner当前Xcode或兼容的最新26版本，同时检查设备/模拟器SDK，再从showdestinations与simctl交集选目标；没有目标时下载所选Xcode的iOS运行时，必要时只为匹配SDK的运行时建立设备，重新核验后测试。不跳过测试、不断言错误已真机/远程复验成功。

本地已执行6个模拟器选择/运行时回归测试并全部通过；shell语法、Python语法、YAML及可选HealthKit配置/entitlement检查通过。新增10个XCTest（总24个）涵盖旧数据解码、覆盖、JSON校验/原子导入、归档幂等、提前结束、时间匹配和计时上下文；Linux未执行XCTest或Xcode编译。此次代码/图标/HealthKit/CI修复的最终结果仍待Actions及真机验收。

### 替代动作追加需求

用户要求器械不可用时切换替代动作，导入格式同步支持。替代项共用动作位置的组数/末组开关，各自有休息和覆盖配置。待训练时可切换，休息/暂停时禁止切换以免遗留系统任务；已完成组数和逐组实际名称保留。当前会话保存原动作快照，可切回；训练中的选择不修改源计划。历史新增可选逐组名称数据，兼容旧记录。导入/复制重新生成替代项ID，全部字段先校验。额外增加3个XCTest（总27个），仍未在Linux执行。新增可直接粘贴JSON的界面及 examples/chest-with-alternatives.json 完整示例。
