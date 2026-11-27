# GymRest Watch与iPhone联动 · 0.9.0 (9)

> 2026-11-27：用户已授权提交Release SDK修复并触发全量打包，配置为bundled/updateOfficial、HealthKit与Watch启用。本地30项脚本检查通过；远程构建结果待确认，不等待结束。下方“未提交”为修复时的历史记录。


> 最新构建复核（2026-11-27）：45856111168的184项iOS测试全部通过，Watch模拟器和手机测试构建成功。Release失败已从diagnostics定位为全局-sdk iphoneos覆盖Watch平台，现改用scripts/build_release.sh保留各目标SDK选择，额外产出release-build.log及Release xcresult。30项本地检查通过；修复未提交、未远程复验、未生成成功IPA。下文早期未执行记录保留作历史，真机与签名仍未验证。

> 2026-11-27复核全量构建45853008444：Watch模拟器编译与手机测试构建已成功，183项iOS测试中181项通过、2项失败，未进入IPA打包。两处修复保留工作区，新增1项边界测试后共184项尚待复验。下文“尚未执行SDK编译”为之前的开发记录；真机、签名及双设备验收仍未完成。

> 2026-11-26：用户已授权提交并打包0.9.0 (9)，包括Watch联动、动作计时/双侧计组、独立素材包与分帧清理。本地27项检查通过；推送后由Actions执行183项iOS测试、Watch模拟器编译和含Watch子包的Release打包，默认轻量IPA并另附素材包。按用户要求不等待远程完成，不确认SDK测试或IPA成功；下方未提交记录为此前工作区状态。

2026-11-26工作区。用户本轮授权开发Watch App与iPhone配对工作，取代此前“Watch App后续再开发”的范围限制。保留此前计时、双侧计组、素材包和图片清理改动；未提交、推送、触发Actions或执行真实设备安装。

## 已实现的代码

- 新增单目标SwiftUI GymRestWatch。部署起点watchOS 10.0（会话镜像最低版本），手机保持iOS 26+；使用Xcode 26 SDK构建。两端共享纯Foundation消息协议，不把手机AlarmKit、SwiftData或图片素材编译进Watch。
- 系统Watch与iPhone配对仍在苹果Watch App完成。GymRest连接页读取WCSession的配对、Watch App安装和即时可达状态；不把“已配对”“已安装”“唤起成功”当作训练正在记录。
- 手机新训练后可请求唤起手表；手表也可为当前手机训练请求关联。请求有效期120秒，用户在手表确认并授权之后再次向手机确认请求仍有效、训练仍活动，才创建传统力量训练会话。开启后才能收集心率、能量；未授权项保持未提供，不填0冒充测量。
- Watch作为唯一健康写入方，使用HKWorkoutSession/HKLiveWorkoutBuilder；手机仅接收镜像/消息和保存已完成健康记录的引用，不重复写一份HKWorkout。
- 手表可完成手机本组/本侧、开始/暂停/继续动作计时，以及控制手机休息；操作发给现有TrainingController，仍使用持久interactionID和串行执行保护。没有离线补计组，也不让手表UI倒计时自动完成组。
- 健康记录暂停/继续和手机休息是独立操作。Watch可自行结束并保存或明确丢弃；手机也可控制GymRest自己的手表会话。不能检测、暂停或结束系统体能训练及其他App的会话，开训前明确提醒避免重复记录。
- 手机训练完成或提前结束后，向对应trainingID/runID发送保存请求。断连时仅此保存命令可排队；开启、计组、暂停/继续等不排队执行。重新连接后不能用旧命令停止新会话。旧镜像对象的断连回调也不能清除新镜像引用。
- 状态带单调序号、唯一会话ID与阶段控制token；心率更新不改变控制token，暂停/继续改变token，阻止迟到的旧暂停覆盖后来的继续。超过45秒未确认的运行状态标为上次状态，连接中断不推断已经结束。
- Watch在真正活动训练中发送状态/采样更新与15秒心跳；没有音频、定位或虚假训练保活。后台行为由真实HealthKit会话及workout-processing模式提供。两端会话恢复使用官方回调，缓存中的running不会直接重新宣称正在采集。

## 保存、去重与历史关联

Watch先持久化会话标识，将trainingID和runID写入HealthKit元数据。保存前按runID查找已保存记录，避免重试再造一条；保存失败保留builder与阶段供重试，恢复时先查已保存结果，再恢复活动会话。停止采集后保存、成功后结束会话；如果崩溃发生在保存成功和end之间，恢复时也尝试结束残留自有会话。不能恢复时明确要求在健康App核对，不补造记录。

已保存回执通过即时消息及可延后的WatchConnectivity传输回手机；手机按sessionID精确查找TrainingRecord。手机尚未归档时暂存，后续归档再关联；已手动关联其他记录时保留原选择并提示。回执幂等，不新增训练历史、不更改完成组数。

TrainingRecord增加可选watchWorkoutReceiptID，完整备份v2继续保留该标记；旧备份缺省nil。用户解除关联后重复到达同一回执不会重新绑回。一个手机训练已保存Watch记录后，不再次开启另一份Watch记录，避免一条手机记录对应多份健康记录；需要新记录时先结束手机训练再开始下一场。

断连期间Watch仍会继续实际采集，直到收到结束请求或用户在手表停止。结束请求包含手机结束时间并限制在该会话起止范围内，但系统已采集的独立健康样本不会被追溯删除；离线长时延及能量统计仍需实测。手机显示“结束请求待确认”不能等同于Watch已经停止。

## 构建与打包

`project.yml`保持可单独构建的手机基础配置，包含共享消息协议；`scripts/watch_project.py`在HealthKit规格上增加Watch目标并生成.gymrest-watch.yml：

- 手机：dev.gymrest.personal。
- 扩展：dev.gymrest.personal.widgets。
- Watch：dev.gymrest.personal.watchkitapp，WKCompanionAppBundleIdentifier精确指向手机。
- Watch Info：WKApplication=true、WKWatchOnly=false、非独立伴侣、健康读写说明与WKBackgroundModes=workout-processing。
- Watch仅声明com.apple.developer.healthkit；没有虚构额外后台授权或App Group。
- 所有目标版本一致为0.9.0 (9)。Watch使用现有品牌生成独立图标集。

macOS可运行：

```bash
GYMREST_HEALTHKIT=true GYMREST_WATCH=true MEDIA_MODE=external bash scripts/ci.sh
```

流程先生成图标/素材/HealthKit/Watch规格，编译通用Watch模拟器目标，再执行手机测试和设备Release构建。打包脚本检查实际GymRest.app/Watch/GymRestWatch.app、父子标识、版本、隐私说明和可执行文件。Actions新增watch_app选项，默认HealthKit+Watch；关闭HealthKit时同时关闭Watch，手动关闭Watch可继续手机构建。签名流程还未配置，没有凭据入库，产物仍为unsigned IPA。

单独生成工程：

```bash
bash scripts/prepare_icon.sh
python3 scripts/prepare_media_project.py
python3 scripts/health_project.py .gymrest-media.yml
python3 scripts/watch_project.py .gymrest-health.yml
xcodegen generate --spec .gymrest-watch.yml --project .
```

## 无Mac的安装验证路径

开发与构建可使用GitHub Actions的macOS环境；用户无需拥有Mac，但编译仍需Apple SDK工具链。开发代码不等于设备已经配对或安装。

1. 后续获授权提交后由Actions产出包含Watch子包的IPA。
2. Windows上安装Apple Devices/iTunes提供Apple Mobile Device Service；下载WatchBridge官方项目Release，USB连接已配对的iPhone。
3. 按WatchBridge提示在手表确认信任、开启开发者模式并重启；用原始含Watch子包的IPA处理两端签名和安装。
4. 打开两端GymRest，在手机“设置 → Watch连接与记录”确认已安装/通信状态，再进行短训练。
5. 首次Watch授权后核对实际running、暂停/继续、保存和健康App里的单一记录；重签后重复验证。

WatchBridge是社区工具，项目报告完整真机流程但其Watch协议实现仍为实验性；GymRest、用户具体设备/系统/签名能力尚未验证。不能承诺免费个人签名可获得全部HealthKit能力。TestFlight可作为付费开发者会员下的另一条分发路径，需要另外配置签名与上传。当前不提供已签名安装包，也没有读取用户Apple ID或签名凭据。

## 本地检查与未完成验收

- 27项Python检查通过，其中5项覆盖Watch规格、父子标识、权限/后台模式、手机基础构建保留、媒体模式叠加及CI/打包入口。
- 新增16项iOS XCTest，项目合计183项；覆盖协议版本与大小、过期请求、状态序号、最终状态不回退、不同会话隔离、暂停控制token、延迟保存、未知计组操作拒绝、双侧半组快照、精确回执关联/重复/未归档/手动关联保留，以及解除关联后的持久去重及备份。
- Swift语法解析相对基线无新增错误；既有AlarmKit文件仍有解析器限制。YAML、Python及shell语法检查完成。
- 当前Linux没有Apple SDK，未运行XcodeGen实际工程生成、Xcode编译、183项XCTest、Watch运行或双设备测试。API按Apple官方文档核对，最终Swift 6隔离/SDK签名、Watch图标与跨平台嵌入仍须Xcode构建确认，不写成通过。
- 真机验收页新增安装通信、授权真实状态、手表计时/双侧计组、手机结束保存与重复去重、断连保存恢复等场景，必须人工完成后勾选。

## 官方API依据（2026-11-26核对）

- [构建多设备训练App](https://developer.apple.com/documentation/healthkit/building-a-multidevice-workout-app)：伴侣标识、会话镜像与真机要求。
- [startWatchApp](https://developer.apple.com/documentation/healthkit/hkhealthstore/startwatchapp(with:completion:))：唤醒伴侣App，完成回调不代表已开始记录。
- [运行训练会话](https://developer.apple.com/documentation/healthkit/running-workout-sessions)：读写授权、真实训练后台处理、采样和恢复。
- [recoverActiveWorkoutSession](https://developer.apple.com/documentation/healthkit/hkhealthstore/recoveractiveworkoutsession(completion:))及[恢复回调](https://developer.apple.com/documentation/watchkit/wkapplicationdelegate/handleactiveworkoutrecovery())。
- [stopActivity](https://developer.apple.com/documentation/healthkit/hkworkoutsession/stopactivity(with:))、[endCollection](https://developer.apple.com/documentation/healthkit/hkworkoutbuilder/endcollection(withend:completion:))、[finishWorkout](https://developer.apple.com/documentation/healthkit/hkworkoutbuilder/finishworkout(completion:))。
- [现代单目标Watch App](https://developer.apple.com/documentation/technotes/tn3157-updating-your-watchos-project-for-swiftui-and-widgetkit)。
- [WatchBridge项目及限制](https://github.com/AdminZachary/WatchBridge)、[TestFlight安装说明](https://testflight.apple.com/)。
