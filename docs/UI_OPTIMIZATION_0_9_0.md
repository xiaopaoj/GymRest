# 训练界面优化（2026-11-27，工作区待审查）

> 更新：当前0.9.1仅iPhone，原Watch状态卡和通信已删除，训练页改用非弹窗健康数据tips。其余UI优化保留，现有本地脚本检查为30项；下方Watch/33项描述是变更过程记录，见[当前方案](HEALTH_ACTIVITY_0_9_1.md)。

参考 Hevy 的实时训练/锁屏入口、Strong 的休息控制和 Fitbod 的动作替换流程，按 P0 → P1 → P2 调整现有原生 SwiftUI 页面。参考交互目的，未复制品牌界面。

## 已实现

1. P0 训练信息层级：当前动作、当前组和训练设置优先；休息状态将倒计时前置；动作安排及破坏性导航归入折叠区。正常且新鲜确认的 Watch 记录折叠为一行；过期、等待确认或异常时展开现有详细状态。
2. P0 直接调整：已填写的重量提供 ±2.5 kg/lb（器械档位 ±1），次数 ±1；未填写时仍通过完整设置明确输入。沿用当前单位与记录口径，不转换、不补猜重量。显示本次上一组实际值，保留预填来源。半组及动作计时期间禁改，按钮走原控制器交互令牌验证与持久化。
3. P0 休息：大号倒计时、±15秒、动作间休息标识与下一动作预设；暂停/继续、结束休息仅在底部操作区展示，去除重复按钮，保留重新开始。
4. P0 双侧：第1侧→第2侧，半组用勾选与文字同时提示“整组尚未完成”；沿用共享 partTitle/completionTitle，两侧顺序由使用者决定。没有新增左右侧数据，也不假定先左后右。到时仍需确认，不自动完成组。
5. P1 快捷训练：每个训练日可星标为唯一常用训练；首页显示常用与上次启动训练日，两者相同时只显示一次。入口打开训练日核对设置和原开训提醒，不绕过开训检查。不固定星期、不猜测下一天。引用已删除训练日的偏好不产生空项目。已有历史不按名称猜测训练日 ID。
6. P1 全局训练条：浏览计划/动作/记录/设置时均可返回正在训练页面；显示当前动作、阶段和组进度，完成后查看结果。训练条只导航，不新增容易误触的直接完成操作。
7. P1 动作替换：计划中配置的原动作和替代动作以列表比较，展示动作缩略图、肌群和器材名称，仍不展示器材图片。只有匹配并安装的素材显示图片；缺图用中性符号，不拿其他动作充数。只解码一张缩略图，尊重媒体包配置/审核帧/背景色。切换使用选择面板打开时的交互令牌，锁屏或 Watch 推进状态后旧面板拒绝操作；已完成动作与重量历史不被重写。
8. P1 记录：列表增加训练时长和动作摘要；详情默认继续展示逐组实际数据，健康记录查询和解除关联收进次级折叠区。
9. P2 视觉：动作预览高度150，保留放大，展开偏好存本机；主要计时操作扩展触控宽度，快速加减至少44点；辅助文字/材质使用系统语义样式；关键控制在辅助功能大字体时竖排，计时字号随文字设置缩放。沿用原橙色主题和四个标签。

## 验证

- 构建前复核后，本地 Python 脚本测试33项通过（包含3项真实CI脚本+模拟Apple命令的失败中止/顺序测试），Swift tree-sitter语法检查与git diff检查通过。语法解析、模拟命令不属于Apple SDK编译。
- 新增 XCTest：旧替代面板令牌被拒绝，更新状态下切换成功，已完成组的动作名称、重量及次数保留。此测试尚未在Xcode执行。
- 当前Linux环境无Xcode，尚未做模拟器截图、SwiftUI类型检查或真机验收。不将本轮界面更新标记为已通过iOS构建。

## 下一次 iOS 验收清单

- 普通计数组、计时组、双侧半组、组间/动作间休息、暂停、结束页面都可见主要操作；小屏及最大辅助功能字号无按钮遮挡。
- 本地修改重量后锁屏完成，记录使用更新预填；快速连点不越过原控制器串行处理；计时中及半组不可修改。
- 替代面板打开后锁屏推进一组，再点击原动作/替代动作，必须拒绝旧面板；关闭重开后可正常操作。
- 常用训练重启后保留、常用与上次相同不重复、删除后不出现失效卡片；已有进行中训练仍从全局条返回。
- Watch运行且新鲜时折叠；超时和报错自动出现详细提示；展开后原暂停/保存/安装入口可用。
- 深色、浅色、VoiceOver、减少动态效果、空记录/无图/素材包切换均核验；健康关联折叠不改变数据或主动查询授权。

参考：
- https://help.hevyapp.com/hc/en-us/articles/35649846517399-How-to-Use-Hevy-s-Live-Activity-on-iOS-and-Android
- https://help.strongapp.io/article/231-rest-timer
- https://help.fitbod.me/hc/en-us/articles/360006335593-Editing-Workouts-in-Fitbod

## 构建前复核补充

- 对照公开镜像iPhoneOS26.0 SDK声明核对新增API（下载用于检查，未安装Apple SDK或Xcode）：
  - https://github.com/xybp888/iOS-SDKs/tree/master/iPhoneOS26.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule
  - https://github.com/xybp888/iOS-SDKs/tree/master/iPhoneOS26.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule
  - https://github.com/xybp888/iOS-SDKs/blob/master/iPhoneOS26.0.sdk/System/Library/Frameworks/ImageIO.framework/Headers/CGImageSource.h
- 将全局训练条、快捷入口、历史行拆开，减少大型SwiftUI表达式推断风险。没有Xcode类型检查结果，不能宣称消除了所有编译风险。
- 真实执行素材/HealthKit/Watch配置生成，检查bundled/updateOfficial、Watch嵌入和新View所在源目录。未运行XcodeGen或链接编译。
- CI先编译Watch Debug、iPhone Debug测试包和设备Release，再启动模拟器执行完整XCTest；Release失败不再等到测试结束才暴露。打包仍在所有测试通过之后执行，不减少测试。失败传播/双份日志经模拟工具回归验证。

复核补充：本轮修改的10个Swift文件语法解析均通过。扩大到82个Swift文件时，tree-sitter在未改动的AlarmKitTimerService.swift产生诊断；与HEAD基线内容及诊断一致，属于本轮无法用此解析器判定的基线语法，不视为新改动通过或新增编译失败。真正的Swift编译器检查仍待Xcode。
