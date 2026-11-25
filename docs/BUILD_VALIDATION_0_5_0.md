# 0.5.0 构建验证 · 2026-11-25

用户已明确要求构建测试，授权提交、推送并触发Actions。本次功能提交为f576586，包含此前未提交的锁屏操作、动作间休息、覆盖导入、模板、动作库、逐组负重及界面调整。

## 第一轮：资源引用失败

[运行45617004858](https://github.com/xiaopaoj/GymRest/actions/runs/45617004858)，代码f576586，结论failure。

Xcode复制ExerciseCatalog.json时，生成的文件引用解析为仓库根目录的ExerciseCatalog.json，而真实文件位于GymRest/Resources/ExerciseCatalog.json。复制失败导致构建取消；114项XCTest尚未开始，不能将这次结果计为测试断言失败。

修复d098f83：移除重复的独立JSON源条目，由现有GymRest目录来源纳入其Resources文件；仍保留Artwork排除项。诊断附件增加生成的project.pbxproj，便于核实工程引用。10项本地Python检查重新通过。

## 排队与运行环境

修复后的macos-26运行45617883473和macos-15 ARM运行45619382734长时间排队，均被后续提交取代取消，未执行测试。工作流改用macos-15-intel；仍严格要求iPhoneOS和Simulator SDK 26，不跳过测试。

## 第二轮：Swift独占访问检查

[运行45619954416](https://github.com/xiaopaoj/GymRest/actions/runs/45619954416)，代码39d2832，结论failure。Xcode 26.3 / iOS SDK 26.2已正确复制动作目录资源。TrainingController在对performances追加时，同时读取所属value的其他字段，触发Swift重叠访问错误。测试尚未开始。

修复ba130fe：先构造SetPerformance快照，再追加到数组。CI日志改为同步tee管道，保证失败诊断完整落盘并上传，不改变pipefail退出语义。

## 第三轮：Swift类型检查复杂度

[运行45622929087](https://github.com/xiaopaoj/GymRest/actions/runs/45622929087)，代码ba130fe，结论failure。PlanArchive嵌套flatMap/map/Set表达式超过Swift类型检查复杂度限制，测试尚未开始。

修复1afef16：改用显式Set<UUID>和循环检查主动作/替代动作ID重复；导出版本检查也拆为循环，保留相同校验和版本规则。10项Python测试重新通过。

## 第四轮：SwiftUI类型检查复杂度

[运行45625635295](https://github.com/xiaopaoj/GymRest/actions/runs/45625635295)，代码1afef16e0b74b768cf7f86aa61cbe2f510bb2b70。结论failure。TrainingView.body的SwiftUI表达式超过类型检查时限，XCTest尚未开始。

修复0bcfd58：将完成页、进度、逐组设置、动作信息、休息控制和导航拆为独立ViewBuilder，保留原交互与状态。CI调整为build-for-testing成功后才启动模拟器并test-without-building，不跳过测试。

## 第五轮：功能与打包通过

[运行45628439706](https://github.com/xiaopaoj/GymRest/actions/runs/45628439706)，代码0bcfd5801a3f00c0f184beec2ca0194ecf930ff3。结论success。Xcode 26.3 / SDK 26.2，114项XCTest实际执行、0失败；iPhoneOS Release构建与未签名IPA结构校验通过，HealthKit分支开启。

下载该次IPA核对时发现主App和扩展的Info.plist仍为XcodeGen默认1.0 (1)，没有使用project.yml的0.5.0 (5)。因此暂不将这个包作为最终0.5.0交付。修复7437a7a：两目标Info.plist显式引用MARKETING_VERSION和CURRENT_PROJECT_VERSION；默认与HealthKit生成配置均已检查。

## 最终版本复验：通过

[运行45631277359](https://github.com/xiaopaoj/GymRest/actions/runs/45631277359)，代码7437a7a86c7d4aad746dea3ea56067fdf1c8cdeb。结论success。Xcode 26.3 / iPhoneOS与Simulator SDK 26.2，macos-15-intel运行器，HealthKit分支开启。

- Debug build-for-testing成功，114项XCTest实际执行、0失败、0 unexpected。
- iPhoneOS Release主App和扩展构建成功，未签名IPA打包与结构校验成功。
- 已从Actions下载最终IPA，核实主App与扩展均为0.5.0 (5)，Bundle ID分别为dev.gymrest.personal及dev.gymrest.personal.widgets，ExerciseCatalog.json已打入主App。
- 10项本地Python测试通过；shell语法、默认/HealthKit项目配置和Git空白检查通过。

[下载IPA压缩包](https://github.com/xiaopaoj/GymRest/actions/runs/45631277359/artifacts/15031488738) · [日志与xcresult](https://github.com/xiaopaoj/GymRest/actions/runs/45631277359/artifacts/15032507557)

IPA SHA256：`f4f581b8ef1cb1d556ff469ddae9783059f5fba45777d80f098d78bf9b0a7e1c`。

本轮修复资源引用、Swift独占访问、类型检查复杂度和包版本字段，未删减或跳过测试。编译仍有界面方向配置的非阻塞警告。此结果不代表SideStore签名、锁屏交互、HealthKit读取、SwiftData旧库升级或全流程真机验收通过；动作动画及器材图素材仍待人工补齐。
