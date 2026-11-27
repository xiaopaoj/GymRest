# 开发进度与技术决策

> 2026-11-27：用户已授权提交并打包0.9.1 (10)。本次包含此前UI优化、手机健康数据tips及Watch代码/构建移除；采用HealthKit启用、external/preserve轻量配置，保留已安装素材。30项本地脚本检查及22个修改Swift文件语法检查通过；Xcode编译、XCTest和真机效果待远程/设备验证。触发后不等待完成，下方“未提交”为开发时历史状态。


## 0.9.1 iPhone健康数据方案（2026-11-27，未提交）

用户明确移除独立Watch App及构建，采用手机只读HealthKit近期锻炼数据辅助判断。已删除Watch源代码/协议/通信菜单、启动和镜像/写入入口、手表目标生成/图标/Actions开关；版本0.9.1 (10)，IPA产物明确标记iPhone。保留旧SwiftData回执字段和备份数据兼容，不删除已有训练/健康关联/素材。

新训练默认手动确认手表运动，可跳过；继续训练不重复。训练页非弹窗tips首次明确请求锻炼分钟数读取，前台每60秒查询近15分钟样本，展示最新样本时间/上次查询。3分钟内有效Watch来源样本仅为活动迹象，旧数据/空结果/异常/来源不明均不宣称运动已开启或关闭；不自动计组、启动、保存健康或结束训练。规则未经真机校准。完整说明与验收见[当前方案](docs/HEALTH_ACTIVITY_0_9_1.md)。

本地30项Python检查通过；包含真实IPA打包器接受iPhone+Widget、拒绝残留Watch的回归。新增9项健康证据与授权/刷新XCTest、1项旧回执备份兼容XCTest，未在Xcode执行；本轮Swift语法与配置检查不等于Apple SDK编译。此前Watch闪退回调修复随Watch实现一并移除，不再作为待发布功能；下方Watch/187项等记录均为历史范围。未提交、推送或触发Actions。


## Watch连接闪退风险修正（2026-11-27，未提交）

用户报告已安装两端，点击连接相关菜单均闪退。未获取.ips或具体按钮，不能确认最终根因。审查发现两端MainActor中的WCSession.sendMessageData回复/错误闭包未显式Sendable；Swift6可能为继承Actor的ObjC回调加入运行时隔离检查，而WCSession会在自己的队列回调。已新增CompanionRequestCallbacks，使用明确@Sendable的continuation回复/失败闭包，两端共用；手表状态发布回调及手机HealthKit镜像入口也显式Sendable，状态读写仍经Task @MainActor。没有调整配对ID、签名凭据、权限或训练数据。

对照公开iPhoneOS26.0 SDK镜像WCSession.h检查回调签名及回复/错误恰有一个被调用的约定。新增2项iOS XCTest，从MainActor发起、后台DispatchQueue调用真实共享回复/错误闭包，检查continuation返回和错误传播；尚未在Xcode执行。与此前UI回归合计预计187项iOS测试。33项本地Python检查通过，本轮Swift改动语法解析通过；无真机闪退已消除的验收结果。待用户提供日志区分swift_task_checkIsolated/_dispatch_assert_queue_fail、隐私TCC/entitlement或其他异常。工作区保留此前UI/构建流程改动，未提交或触发远程打包。


## 界面改动构建前复核（2026-11-27，未提交）

复核新增SwiftUI和ImageIO调用，对照公开镜像的iPhoneOS26.0 SDK SwiftUI/SwiftUICore接口及CGImageSource.h确认AnyLayout、ScaledMetric<CGFloat>、DynamicTypeSize.isAccessibilitySize、onChange(initial:)、ViewThatFits和缩略图API声明。镜像源为xybp888/iOS-SDKs（非本机安装SDK）。拆分全局训练条、快捷训练列表和历史行，缩小复杂ViewBuilder的类型推断范围；未发现明确语法/API声明不匹配，不能据此认定编译通过。

将Release设备编译前移至build-for-testing之后、模拟器启动和XCTest之前；成功构建仍执行全部测试。新增3项真实ci.sh+假Apple工具流程回归，验证Debug失败提前退出、Release失败不启动模拟器/测试且保留双份日志、成功时编译→启动→测试→打包顺序。共33项Python检查通过。真实生成bundled/updateOfficial+HealthKit+Watch配置并检查新文件包含于GymRest源目录，官方包存在。本机无Xcode/swiftc，185项iOS测试（含新增1项）与SwiftUI类型检查仍待远程验证。未提交、推送或触发新的Actions。


复核补充：本轮修改的10个Swift文件语法解析均通过。扩大到82个Swift文件时，tree-sitter在未改动的AlarmKitTimerService.swift产生诊断；与HEAD基线内容及诊断一致，属于本轮无法用此解析器判定的基线语法，不视为新改动通过或新增编译失败。真正的Swift编译器检查仍待Xcode。

## 训练界面顺序优化（2026-11-27，未提交）

按用户确认依次实现训练页层级、直接调整重量/次数、休息控制去重、双侧半组进度、首页常用/上次训练、跨标签训练返回条、带动作缩略图的替代列表及记录摘要；大字体控制适配、系统语义颜色和图片展开偏好同步调整。替代动作新增交互令牌校验及保留已完成组数据的XCTest回归。完整范围与真机验收表见[界面优化记录](docs/UI_OPTIMIZATION_0_9_0.md)。本地30项Python脚本测试通过；Swift语法解析通过不代表Xcode编译。新XCTest、模拟器布局和真机Watch/锁屏仍待验证，本轮未提交、推送或触发Actions。


> 2026-11-27：用户已授权提交Release SDK修复并触发全量打包，配置为bundled/updateOfficial、HealthKit与Watch启用。本地30项脚本检查通过；远程构建结果待确认，不等待结束。下方“未提交”为修复时的历史记录。


## Release跨平台SDK修正（2026-11-27，未提交）

已确认[全量构建45856111168](https://github.com/xiaopaoj/GymRest/actions/runs/45856111168)的184项iOS测试全部通过，Watch模拟器及手机测试构建成功。失败发生在Release：ci.sh的全局`-sdk iphoneos`覆盖了Watch目标的watchos配置，actool用`--target-device iphone --platform iphoneos`处理WatchAssets，报AppIcon无适用内容。已提取scripts/build_release.sh，移除全局SDK覆盖，由generic iOS destination及各目标配置选择iOS/watchOS SDK；另存Release日志和xcresult。新增3项脚本执行回归，本地共30项检查通过。修复未提交、推送或远程复验，尚无成功IPA；下一次获授权仍须完成带775张素材与Watch的全量迁移构建。

> 2026-11-27：用户已授权提交本次两处测试修复并继续此前全量构建。将以bundled/updateOfficial、HealthKit和Watch启用的配置复验184项iOS测试并打包；本地27项检查已通过，远程结果待确认。按用户要求触发后不等待结束，后续默认仍为轻量；下方“未提交”为此前修复记录。

## 0.9.0构建测试失败修复（2026-11-27，未提交）

已核对全量构建[45853008444](https://github.com/xiaopaoj/GymRest/actions/runs/45853008444)完整日志：Watch通用模拟器编译及手机build-for-testing成功；183项XCTest执行181项通过、2项失败，流程未到Release打包，未生成IPA。这不代表Watch真机授权、签名或设备联动通过。

- 修复旧名称自定义动作的历史重量预填：无prescription时仅使用有效catalogID的目录默认值；不再凭名称把旧“总重量”口径改成“器械标重”，导致历史profileKey不匹配。已有预设优先，历史数据不改写。新增显式ID与仅名称边界测试，并增强原旧名称回归断言。
- 修正半组提前结束的测试假设：首次整组完成前逐组记录采用延迟创建，nil合法且不代表完成一组。断言改为严格核对唯一历史、0整组、提前结束、没有任何逐组记录、活动快照清除及提醒取消；没有修改半组计组逻辑。

本地27项Python检查通过；修改过的Swift语法解析与diff检查通过。新增1项iOS测试，现共184项；当前修复尚未在Xcode复验，也未提交、推送或触发重打包。上一轮用户要求的“带775张素材+Watch、更新官方包”的全量迁移构建仍需成功完成，此后再默认轻量。

> 2026-11-26：用户已授权提交并打包0.9.0 (9)，包括Watch联动、动作计时/双侧计组、独立素材包与分帧清理。本地27项检查通过；推送后由Actions执行183项iOS测试、Watch模拟器编译和含Watch子包的Release打包，默认轻量IPA并另附素材包。按用户要求不等待远程完成，不确认SDK测试或IPA成功；下方未提交记录为此前工作区状态。

## 0.9.0 (9) Watch联动工作区

已新增GymRest Watch伴侣目标（watchOS10+）、WCSession通信与HealthKit会话镜像；手机请求/手表确认授权、真实记录状态、手表操作手机计组/计时/休息、暂停/继续/保存/丢弃、手机结束请求精确回传及历史回执去重。手机仍为健康只读与引用关联，只有Watch写入。构建新增可选Watch嵌入与实际子包检查。详见[Watch实施说明](docs/WATCH_COMPANION_0_9_0.md)。未提交、推送或打包；SDK/签名/真机尚待验证。

## 0.8.0 (8) 当前工作区

已实现动作目标计时与两侧计组、系统动作提醒及锁屏操作；独立素材包导入/导出/匹配/回滚和external/bundled构建；可选Watch新训练前手动提醒。计划按内容导出v4、完整备份v2，旧数据兼容。独立Watch App按用户确认留待后续。详见[0.8.0实施记录](docs/TIMED_MEDIA_0_8_0.md)。保留工作区，未提交或打包。

## 素材包与Watch开训提醒规划（未实现）

已按需求完成[独立素材包与Watch提醒规划](docs/MEDIA_PACK_AND_WATCH_PLAN.md)：轻量/含包IPA、保留/升级官方包策略、版本化校验导入与回滚；当前仅方案，未改变运行时代码或打包。Watch官方能力支持自有伴侣App会话镜像，不能据当前只读健康记录判断系统体能训练是否开启。

## 图片清晰度与重复帧修正（2026-11-26，未提交）

已完成高相似候选的人工清晰度/冗余复核：39组取消展示47帧，窄距杠铃卧推保留原第1、3帧。随包目录、来源审核及导入脚本清单同步；912张源文件不修改，当前775帧用于280项动作。详见[分帧复核](docs/FRAME_QUALITY_REVIEW.md)。17项本地检查通过；保留工作区，未提交、推送或打包。

> 2026-11-26：用户已授权提交并打包0.7.0 (7)。本地16项检查通过；推送后由Actions执行143项iOS测试和Release打包。按用户要求不等待远程结束，当前不确认测试或IPA成功；下方“未提交/打包”为此前工作区记录。

## P1动作资料与设备验收（2026-11-26工作区）

已加入306项结构化步骤/常见错误与变式备注、补齐原3项的6张Everkinetic原图，并对906张原分帧及补图做一般视觉核对。25组暂停展示、10组部分保留，全部静态；单双臂绳索侧平举拆分，当前280项有图。健康查询增加可测试流程/时间窗诊断，锁屏增加同步时间，设置新增分版本人工验收页。真机无法在Linux执行，尚无设备通过结论。见[P1处理记录](docs/P1_QUALITY_AND_DEVICE_REVIEW.md)。未提交或打包。


## 0.7.0优化工作区（2026-11-26）

已加入导入字段诊断/匹配预览、完整备份与合并恢复、305项中文名、固定训练操作区、图片折叠/放大、预填来源与上一组复用、锁屏累计组数反馈、按实际动作口径查看历史变化。保留旧数据与关联校验，不增加Watch App或健康写入。详见[优化说明](docs/OPTIMIZATION_0_7_0.md)。仅保留工作区，未提交或构建。


> 0.6.0 (6)已提交并推送：首轮编译成功，125项测试出现4处断言失败，已修复并推送e26aa96。Actions运行45770816141后台复验；用户要求提交后不等待打包，当前不确认IPA成功。详见构建记录，下文“尚未提交/构建”是此前工作区记录。

## 统一校对名称（2026-11-26）

四项规范名统一用于动作库、新建/编辑/导入计划及新训练，原名仅作兼容别名。已有计划中明确匹配项事务更新，失败回滚，损坏或非法旧计划跳过；历史和活动快照不改写。旧自定义名称的负重匹配键在比较时兼容规范名，保留历史预填。

## 动作素材导入 · 0.6.0工作区（2026-11-26）

Workout Guide固定版本的906张PNG已导入；原动作匹配48项，补充254项，总305项。训练页与详情可按catalogID或规范化中英文名称/别名显示图片，支持手动切帧及可选分帧播放。器材图片和占位提示移除。已按三帧复核规范对握下拉、曲杆弯举、行进箭步蹲和器械提踵名称；对握下拉已匹配原动作。其余新增动作保留源英文名称及粗粒度肌群，未确认模式不参与顺序建议。原图、CC BY-SA 4.0署名及逐帧来源随包保存。详见[素材导入记录](docs/WORKOUT_GUIDE_IMPORT.md)。未提交、推送或构建。



## 旧版空白数据清理 · 2026-11-26（工作区）

按用户补充要求，将仅隐藏升级为一次性持久化清理。启动TrainingStore时，仅移除默认五个名称（胸部/背部/腿部/肩部/手臂训练）、动作可正常解码且为空、未归类或归属“五分化模板”的旧训练日；删除其清空后的默认父计划。有动作、损坏数据、自定义名称或其他分组中的空白项保留。可空迁移标记与删除在同一save内提交，失败回滚，下次可重试；以后新建的空白项不反复删除。新安装只建立偏好，不再自动创建空白五分化。首页移除旧版空白折叠区，其他未归类训练仍可访问。训练历史、健康关联和活动快照不参与删除。未提交、推送或触发Actions。

> 0.5.0 (5)已提交、推送并通过构建验证：10项本地Python测试、114项XCTest（0失败）、iPhoneOS Release构建及IPA结构检查通过。已下载核实主App与扩展版本、Bundle ID和动作目录资源。真机覆盖安装、锁屏交互及SideStore重签仍待验收；媒体仍待人工补齐。详见[本轮构建记录](docs/BUILD_VALIDATION_0_5_0.md)，下方为各阶段历史记录。

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
