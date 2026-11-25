# 锁屏训练操作 · 2026-11-25

## 使用流程

在 App 内选择训练日并开始训练；首次提醒授权在 App 内完成。随后可在锁屏的 GymRest 训练卡片上操作；支持灵动岛的机型长按展开后使用相同按钮。

- 做组期间：显示动作与组数，点击「完成本组」保存一次完成记录，并按原规则注册休息提醒。默认末组直接到下一动作或结束训练，末组休息开关继续生效。
- 休息期间：显示倒计时，可暂停、加15秒、结束休息；暂停后可以继续。提前结束休息会先取消旧提醒，不计为完成下一组。
- 提醒到时后：系统负责提醒。App 在后台时不依赖持续执行代码来切换训练状态；点击「结束休息」确认进入下一组，再做组、点击「完成本组」。回到 App 时仍按系统状态自动校准。
- 注册失败：卡片明确显示「提醒未注册」及错误，保留已确认的组数；提供「重试提醒」与结束休息入口。无提醒权限时锁屏操作不新增完成组数，提示先打开 App 授权。
- 正常结束或提前结束训练后清除训练卡片。卡片被关闭或未获系统显示时，可回到 App 继续操作；训练页提供重试显示入口。

系统可能要求 Face ID 等解锁认证，不能保证完全未解锁时可直接操作。卡片展示、后台唤起、SideStore重签后Intent/扩展可用性需要真机验收。

## 选择实时活动的原因

普通桌面小组件的时间线刷新不适合驱动实时训练状态。新增独立的训练 Live Activity，持续覆盖做组/休息/暂停阶段；不通过假计时或延长闹钟维持卡片。

现有 AlarmKit 系统提醒与其休息实时活动保留，训练卡片不负责响铃。休息期间系统可能同时展示训练卡片和 AlarmKit 休息卡片；不能移除系统提醒来追求单一卡片。交互按钮位于 GymRest 训练卡片。通知降级也可使用训练卡片，但通知能力与 AlarmKit 不等效。

本轮未增加普通桌面Widget、Watch App、App Group、推送服务或后台保活权限。

## 数据与并发

- 共享的 `LiveActivityIntent` 在主 App 进程执行，`openAppWhenRun`为false。AppRuntime统一打开并缓存容器、TrainingStore和TrainingController；App界面与后台Intent复用同一控制器，不让扩展直接打开第二份数据库。
- 控制器每次持久化状态时更新可选interactionID。旧版快照缺少该字段时补充并持久化，不更改已有动作、组数和会话ID。
- Intent携带卡片的interactionID。操作前和每次异步预检查后核对标识，过期卡片只刷新状态，不推进下一组。控制器已有busy保护继续覆盖注册和取消，Live Activity更新串行执行并等待完成。
- 所有操作复用App现有完成组/暂停/继续/调时/跳过休息路径，提醒取消失败不能前进。系统计时、手动计组、归档去重规则保留。
- 异常训练快照或存储打开失败时禁用卡片操作，并提示回App恢复；不删库。提醒权限后台预检不弹授权请求，不把注册失败伪装为提醒成功。

## API依据与验证

已读取Apple官方Markdown文档：

- [LiveActivityIntent](https://developer.apple.com/documentation/appintents/liveactivityintent.md)：后台启动App进程执行Intent，无需打开App界面。
- [交互式Widget与实时活动](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities.md)：按钮Intent、App进程执行、锁定设备的认证要求及错误状态更新。
- [Activity.request](https://developer.apple.com/documentation/activitykit/activity/request(attributes:content:pushtype:).md)：前台或LiveActivityIntent中创建活动，后台允许更新/结束。

新增QuickActionTests 14项，总78项XCTest。覆盖完成并注册、重复/过期按钮、暂停加时继续与取消、未授权不计组、注册失败重试不重复计组、冷恢复最终组归档幂等、旧快照字段兼容、末组休息、取消失败及异步预检期间状态变化。

本地6项Python回归、shell/Python语法、YAML/健康构建条件与Git空白检查通过；Swift语法解析相对基线无新增问题。这些不能替代Xcode类型检查。本轮78项XCTest、iOS编译和真机交互尚未执行；此前64项成功仅适用于1965214。

依仓库既有约定，本轮优化保留工作区，不提交、不推送、不触发Actions，等待用户后续通知。


## 切换其他App等待提醒，再锁屏做组

用户补充的常用流程：切到其他App等待组间休息到时，提醒后锁屏做组。为避免回App或再次在训练卡片上结束休息，AlarmKit训练提醒的停止按钮改为「结束休息」，并附加RestFinishedIntent。

点该按钮时系统先处理停止提醒，再在App进程执行Intent，按原timerID核对当前休息、取消残留提醒并持久化进入下一组；末动作末组休息则正常归档。该操作绝不额外完成训练组。重复回调、已替换/结束的旧timerID忽略；取消失败保留错误与当前进度。独立提醒测试不附加训练回调。

锁屏训练卡片随后显示「完成本组」；做完一组后点击，开始下一次休息，无需切回App。若只按电源键锁屏或以其他方式静音，没有已确认的Intent回调保证，不把这种动作当作结束休息或完成一组；卡片仍提供手动结束休息入口。通知降级暂不接入系统通知操作，继续使用训练卡片。

API依据：已读取[Apple AlarmKit官方示例](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit.md)，系统自动处理stop，stopIntent可附加业务操作；没有改用会打开App的secondaryIntent。

新增4项停止提醒衔接测试：准备下一组不计组、重复/过期提醒隔离、取消失败、最终休息归档幂等。全项目78项XCTest尚未执行；本地检查结果不等于锁屏/其他App前台时实际回调已真机验证。


## 动作间休息追加

新增独立动作间时长后，卡片与系统提醒明确显示动作间休息及下一动作。完成本动作末组、停止相应休息提醒后只切换到下一动作，不计该动作任何组数。后台提醒权限预检同样覆盖本动作末组需要动作间休息的情况。新增8项动作间回归后共86项XCTest，尚未执行；之前78项/74项为当时的测试数量。
