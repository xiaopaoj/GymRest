# 开发进度与技术决策

> 最新工作区为0.5.0：模板/51项动作数据/顺序建议/逐组重量与可选次数/界面优化已接入源码；10项本地Python测试通过，114项iOS测试待运行。动作演示与器材图片尚待人工补齐，未提交或推送。当前状态详见 [模板与负重说明](docs/TEMPLATES_AND_LOADS.md)；下方旧阶段记录不代表最新验收结果。

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

## 0.4.0 工作区更新：计划层级与开始流程

用户确认“五分化”为上层训练计划，导入文件的五个plans是训练日。增加TrainingProgram与TrainingPlan.programID；不自动推断/清理旧数据，提供显式整理和同名空项目转换。首页改为上层计划卡片与底部计划/记录/设置，训练日详情底部统一开始；空白项目收起。v1导入可指定分组，v2往返保留分组，提供用户文件转换后的examples/five-day-split.json。

审查发现后台同步持有用户操作busy锁，存在用户开始被丢弃的路径。已分离只读查询与用户动作并增加revision检查；开始前验证动作，失败显式提示，持久化失败还原内存。该改动未真机复验，不能断言覆盖用户所有无响应原因。详情见 docs/INTERFACE_REVIEW.md。

增加7个XCTest，总34个，尚未执行；本地6个Python回归测试与静态检查通过。按照用户最新指令，本轮不提交、不推送、不触发Actions，保留工作区等待通知。

## 审查修复收尾（工作区，未提交）

继续完成审查问题：训练全屏页错误展示、动作编辑保存失败保留草稿和回滚、固定确认弹窗操作对象、上层计划整套复制、启动失败恢复完整内存标记、系统暂停0秒清理、外部恢复截止时间校准、末组提示与实际行为一致。具体修改和证据见 docs/INTERFACE_REVIEW.md 收尾表。

新增11个ReviewRegressionTests，目前45个XCTest均待本轮Xcode执行。本地6个Python回归与静态检查通过；不提交、不推送、不触发构建，等待用户通知。

## 用户授权提交本轮修复

用户已明确授权提交、推送并触发构建。此次提交包含0.4.0层级调整及审查修复；历史“未提交”描述反映当时状态。推送后继续下一轮审查与优化，新增优化先保留工作区，不追加推送。构建结果待实际确认。

## 推送后第二轮优化（工作区未提交）

此前审查修复已按用户授权推送为eb4329b，已确认Actions第6次运行；检查时仍在运行。随后继续进行第二轮审查，完成通知绝对时间防漂移、历史按ID查询、首页单次统计、恢复/写入状态校验、中文权限、默认秒数输入、前后台同步取消、数据打开重试与常亮释放等优化。详见docs/SECOND_REVIEW.md。

新增11个OptimizationTests，共56个XCTest未执行。本地6个Python回归及静态检查通过。这批优化未提交/推送，与正在构建的基线明确分开。

## 第三轮审查：升级数据保留（未提交）

核对生产SwiftData持久化、固定Bundle ID、HealthKit构建和删除路径，没有升级清空历史逻辑；同一应用身份覆盖安装通常保留数据，但真实跨版本/SideStore升级未验收。现有JSON仅导出计划，完整历史备份和显式版本迁移仍是优先优化点。

新增磁盘重开测试3项及坏活动状态保护测试3项，总62个XCTest未执行。代码优化包括记录详情逐组名称一次解码，以及快照异常与数据库I/O异常分离：快照坏时开放计划/历史浏览，保留原数据并阻止开始、结束覆盖或提醒测试，提供重试。真实数据库故障仍上抛存储错误页。详见docs/DATA_UPGRADES.md。本轮仍未提交、推送或构建。

## 用户构建日志：45项测试1失败

已读取用户上传日志：模拟器App与测试编译后实际执行45项XCTest，44通过、动作编辑保存失败回滚测试失败。CoreData默认目录错误后明确恢复成功，未阻止测试。现有脚本在test失败后停止，不能声称Release IPA生成。

工作区修复采用处理pending changes后回滚的统一入口，动作数据原始快照兜底，保留原断言和错误传播；创建Application Support父目录但不改数据库位置。新增2个回归测试后共64项未重新执行，详见docs/BUILD_FAILURE_2026-11-25.md。本地6项Python和静态检查通过，未提交或触发构建。


## 2026-11-25 续接验证

云环境已恢复；Actions列表与完整失败日志直接读取均为HTTP 200，日志访问阻塞已解除。远程最新运行仍为eb4329b，45项测试中1项回滚断言失败。当前工作区64项XCTest尚未在Xcode执行；6项Python回归及本地脚本/配置/空白检查重新通过。未提交、推送或触发远程构建，详见docs/BUILD_FAILURE_2026-11-25.md。


## 2026-11-25：Actions验证通过（1965214）

用户已明确授权提交、推送并触发Actions。代码提交 `1965214a985290aa2de5825b7b93802ef06ac308` 已推送main；[运行45581759118](https://github.com/xiaopaoj/GymRest/actions/runs/45581759118)最终结论success。

直接下载完整日志确认：64项XCTest执行、0失败，`TEST SUCCEEDED`；原失败的 `testFailedExerciseCommitRollsBackAndRetainsDraftValue` 和磁盘重开保护测试 `testFailedEditLeavesDiskPlanAndHistoryUnchangedAfterReopen` 均通过。iPhoneOS Release构建 `BUILD SUCCEEDED`。已上传 `GymRest-healthkit-unsigned` 与 `GymRest-diagnostics` 两个附件。

这次验证覆盖模拟器测试、未签名设备构建和IPA打包；真机交互、系统提醒及实际签名/HealthKit授权仍以真机验收为准。此前“64项尚未执行”是本次运行前的历史状态。


## 锁屏交互优化（工作区，未提交）

新增覆盖做组/休息/暂停的训练实时活动，锁屏及展开的灵动岛支持完成本组、暂停/继续、加15秒、结束休息与注册失败重试。LiveActivityIntent复用主App缓存运行时和训练控制器；每次持久化旋转进度标识，异步预检后复核，旧卡片不多计组。后台缺少权限时不请求授权、不计组。AlarmKit提醒与原系统休息卡片保留，可能同时显示两张卡。

新增10个回归，总74项XCTest，尚未在Xcode执行；本地6项Python回归及静态检查通过。此前64项通过不代表本轮通过。未提交/推送/触发Actions，详见docs/LOCK_SCREEN_CONTROLS.md。


### 其他App等待提醒、锁屏做组的衔接

AlarmKit训练提醒新增stopIntent，点「结束休息」后核对原timerID并进入下一组，不计为完成下一组；旧ID和重复回调忽略。仅锁屏/硬件静音不能假定触发业务回调，保留训练卡片手动结束休息。新增4项测试后总78项XCTest未执行；本地6项Python与静态检查通过，尚未提交/推送/触发Actions。需真机验证其他App前台时停止提醒后无需进入GymRest、锁屏可完成下一组。详见docs/LOCK_SCREEN_CONTROLS.md。


## 动作间休息配置（工作区，未提交）

补充主动作可选transitionRestSeconds（0–86400，0为直接切换），区分组间、动作间与训练结束后休息。完成当前动作末组后，先保留当前动作休息，结束/跳过后才前进；不叠加两段计时，最终动作不执行动作间休息。App/锁屏权限预检、系统提醒及卡片共用相同规则。替代项共用动作间配置，独立组间配置保留。

旧JSON/存档缺少字段时保留旧行为，不自动变更计划；App编辑动作时可明确配置，新建动作默认取当前默认休息值。导入导出、复制、记录快照保留配置。说明见docs/PLAN_JSON.md，示例examples/transition-rest.json。

新增TransitionRestTests 8项，总86项XCTest尚未在Xcode执行；本地6项Python与静态检查通过，不能扩大为新版iOS通过。仍未提交、推送或触发Actions。

待真机验收：组间45秒/动作间180秒分别正确；0秒直接切换；末动作直接结束或按显式开关额外休息；动作间暂停/恢复/锁屏结束提醒只前进一次；覆盖更新保留旧计划及正在训练的快照。


## 覆盖导入选项（工作区，未提交）

文件和粘贴导入新增追加（默认）、覆盖所选计划、覆盖全部计划。确认页展示冻结的输入文件、目标、导入列表与本地移除范围。所选覆盖保留目标上层计划ID/名称，替换其全部训练日；全库覆盖重建分组，包含未归类内容。均不按名称猜测合并，训练日/动作重建ID。训练记录、健康关联、当前快照和偏好保留。

服务在提交前校验已确认文件和目标快照，遇到目标变化/未保存编辑即拒绝，不保存或丢弃其他草稿。删除和追加使用一次save，保存或构造失败回滚。空文件禁止覆盖。新增ReplacementImportTests 11项，项目共97项XCTest尚未在Xcode运行；6项本地Python回归及静态检查通过。本轮代码尚未提交、推送或触发Actions。

待验收：两种输入方式均展示相同预览、取消零修改、覆盖范围明确、保存失败恢复原计划、正在训练时覆盖不改变当前进度、覆盖后下一次训练使用新配置。详见docs/PLAN_JSON.md。


## 已确认开发：0.5.0模板、动作与负重

用户确认PPL三分化、胸/背/腿/肩/手臂五分化、每组重量及可选次数，先建立免费来源动作数据，缺少素材可后续人工补充，并要求同步优化界面。已建立51项离线目录、模板定制、重点排序建议、训练/锁屏记录与历史逐组显示；计划JSON扩展为version3，兼容旧版。新增17项XCTest后共114项未执行，本地10项Python与静态检查通过；当前Linux不能验证Xcode类型或设备UI。21个动作的37个公开视频候选已整理，抽样风格不一致，全部媒体保持pending，没有混入App。未提交/推送/触发Actions。详见docs/TEMPLATES_AND_LOADS.md。
