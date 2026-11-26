# GymRest

> 用户已于2026-11-26授权提交打包：正在提交0.6.0 (6)并执行Actions验证。最终结果待返回，下文“尚未提交/构建”是此前工作区记录。

工作区新增0.6.0 (6)：导入906张动作分帧图片，48项原动作配图、254项新增动作，训练页可直接查看；器材图片不展示。包含旧版空白数据清理。尚未提交或构建，以下0.5.0下载包不含本轮改动。见[素材导入记录](docs/WORKOUT_GUIDE_IMPORT.md)。

当前版本0.5.0 (5)：三分化/五分化模板、51项动作目录、训练顺序建议、逐组重量与可选次数，以及同步界面优化。114项XCTest零失败、Release构建与IPA检查通过；媒体待人工补齐。完整状态见[构建记录](docs/BUILD_VALIDATION_0_5_0.md)。见[本轮说明](docs/TEMPLATES_AND_LOADS.md)。


[下载0.5.0 (5)未签名IPA压缩包](https://github.com/xiaopaoj/GymRest/actions/runs/45631277359/artifacts/15031488738)（解压后用SideStore签名安装）。

此前0.4.0基线已完成64项iOS测试与Release构建；本轮0.5.0已独立通过114项iOS测试与Release构建。计划层级的历史审查见 [界面与使用流程审查](docs/INTERFACE_REVIEW.md)。

轻量原生 iOS 26+ 个人健身组间休息计时器。SwiftUI + SwiftData + AlarmKit，无账号、后端或广告，训练计划和记录保存在本机。

## 0.5.0 新增

- 三分化/五分化模板，可选择每周目标、器材、具体动作及重点部位后预览创建。
- 51项离线动作资料，支持部位/器材筛选、要点与替代选择，保留来源和许可。
- 顺序建议说明原因，由用户采用；训练中只调整未开始动作。
- 每组重量、可选次数、单位、负重口径与器械备注；实际记录与计划预设分离，锁屏完成沿用当前组设置。
- 独立动作间休息、锁屏快捷操作及追加/覆盖导入，已通过本轮Xcode编译与自动化测试，仍待真机验收。
- 计划JSON version3，旧版兼容；演示及器材图待补充，不宣称素材齐备。

## 历史 0.3.0 功能记录（不代表最新工作区状态）

- 首次创建胸、背、腿、肩、手臂五套可编辑空白计划；支持添加、重命名、删除、复制和排序。
- 动作独立配置组数、休息秒数、末组后是否休息；支持复制、拖拽排序及快捷秒数。器械被占用时可切换预设替代动作，保留组数并逐组记录实际动作。
- 点击“完成本组”进入休息，默认末组直接切换动作；训练不会自动完成组数。
- 休息可暂停、继续、跳过、重启及 ±15/30 秒；临时调整不修改计划。
- 当前训练进度本地保存，恢复时核对系统提醒和 Live Activity 截止时间。
- 设置默认组数/休息、提醒方式、权限及训练页面常亮；保留独立提醒测试入口。
- 计划 JSON 导入导出：追加导入、支持文件或直接粘贴文本，全量校验、不覆盖现有计划，见 [格式说明](docs/PLAN_JSON.md)。
- 动作配置折叠的按组休息覆盖；灵动岛/锁屏显示动作、完成组数与下一步，点击返回训练。
- 训练完成或提前结束后保存记录，可查看、删除并手动关联健康运动；见 [HealthKit说明](docs/HEALTHKIT.md)。
- 全新深色橙色计时圆环＋哑铃 App 图标，构建时通过系统 sips 生成标准1024图标资源。

用户已决定先开发 App，暂缓 SideStore 验证。后续已收到部分真机安装和提醒成功反馈，详见 [真机验证记录](docs/DEVICE_TEST_2026-11-25.md)，不代表当前版本完整验收；现在支持 JSON 导入导出、指定组休息覆盖和训练记录；新增可选健康运动匹配。

## 使用流程

1. 编辑计划，添加动作并分别设置组数与休息。
2. 在设置中申请 AlarmKit 权限，或显式选择本地通知降级并申请通知权限。
3. 开始训练，每练完一组点击“完成本组”；休息结束后手动开始下一组。
4. 收起训练页不会结束训练；首页可继续。提前结束会取消系统提醒、归档本次记录并删除临时状态。

开始训练时保存计划副本；编辑/删除原计划不影响当前训练。跳过的组不算完成，返回上一动作会重置该动作组数，操作前会确认。

本地通知无法保证突破静音、专注模式，不提供 AlarmKit 锁屏倒计时。暂停通过取消当前系统任务实现，继续时重新注册剩余时间；暂停时不会响铃。

## 构建与安装

GitHub Actions `iOS 26 validation and unsigned IPA` 支持 main 推送、PR 和手动触发。使用 macos-15-intel、iOS 26 SDK 和 XcodeGen。默认成功后下载 `GymRest-healthkit-unsigned`（手动关闭healthkit时为 `GymRest-unsigned`），诊断日志和 XCTest 结果在 `GymRest-diagnostics`。

macOS 开发环境可运行 `bash scripts/ci.sh`。Linux / Windows 无法直接编译 Apple SDK。先执行 `bash scripts/prepare_icon.sh`，再用 XcodeGen 生成工程。工程由 `project.yml` 生成，构建目录不入库。

CI 会选择同时包含 iPhoneOS / Simulator SDK 的 Xcode 26，并用 scheme 的可用目标列表验证模拟器，避免只根据 simctl 选择不兼容运行时。没有可用目标时尝试安装所选 Xcode 的 iOS 运行时并重新检查；下载失败会保留日志并失败，不跳过测试。

默认Actions编译只读HealthKit版本，但不自动申请权限。Apple官方能力表支持Apple账户持有者使用HealthKit，仍需验证SideStore保留entitlement及真机授权。手动构建取消 `healthkit` 可取得不含该能力的版本。

[SideStore 指南](docs/SIDESTORE.md) · [测试及验收](TESTING.md) · [开发决策](DEVELOPMENT.md) · [已知限制](KNOWN_ISSUES.md)

含替代动作的可导入示例：[chest-with-alternatives.json](examples/chest-with-alternatives.json)。
