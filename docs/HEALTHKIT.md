# Apple Watch / 健康运动记录匹配

## 可以读取什么

GymRest 通过 iPhone 的 HealthKit 读取已同步到“健康”App 的 workout 运动记录，不直接连接手表，也不需要开发 watchOS App。Apple Watch 或其他手环的数据只有在对应来源写入健康App、用户授权且 GymRest 签名支持 HealthKit 时才可能被查询到。不能读取任意手环的私有数据库。

只读运动类型、开始/结束时间、来源及可用的设备说明；不读取心率、体重等额外类型，不写入或修改健康运动。授权只在训练记录详情点击查询时申请。权限可在系统健康/隐私设置中撤销。没有自动后台同步、账号或服务器。

## 签名与构建

HealthKit capability 需要 `com.apple.developer.healthkit` entitlement 与匹配的签名配置；只把 entitlement 写进未签名 IPA 不会获得系统权限。Apple官方能力表的“Apple Developer”列对HealthKit标为支持，该列说明为Apple账户持有者，因此不能将付费会员视作必要前提。SideStore仍需要保留正确entitlement；不能以此前普通包可安装推断健康版本已获正确签名。

默认 Actions 构建启用只读HealthKit代码，生成 `GymRest-healthkit-unsigned` Artifact；授权依然由用户在记录详情主动触发。手动 **Run workflow** 取消勾选 `healthkit` 可生成无健康能力的 `GymRest-unsigned`，训练记录始终可用。这个版本增加只读 `NSHealthShareUsageDescription`，仍是未签名 IPA，需要使用具备能力的配置完成签名。无需为本地训练记录开通健康能力。未签名构建不会自动把entitlement写入签名；所需 `HealthKit.entitlements` 同时保存在诊断Artifact中，后续签名工具须支持并实际授予该能力。

本项目不要求或接收 Apple ID 密码、证书及私钥。当前 HealthKit分支尚未完成实际编译/签名/授权验收。

## 匹配方式

1. 在“训练记录”打开一条带开始时间的记录。
2. 点击“授权并查找时间相近的运动”。
3. 查询训练时间前后各15分钟窗口内相交的运动，按时间重合比例排序。
4. 检查日期、运动类型、来源/设备，再手动确认关联。

时间重合并不保证同一训练；不会自动关联，不会自动完成训练组。设备来源可能缺失，也可能来自其他App，不能把所有候选标为 Apple Watch。仅存关联 UUID、来源和开始/结束时间，可解除关联。删除本机训练记录不会删除健康App原记录。

HealthKit 为隐私保护不告诉 App 用户是否拒绝读取；授权调用结束也不证明获准读取。空结果可能是未授权、没有记录、数据未同步或可读时间窗口受限，不作确定推断。旧活动状态缺少开始时间时不猜测开始时间，不提供匹配。

## 官方依据（2026-11-25 已读取）

- [Authorizing access to health data](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)：逐项授权、能力声明和读写用途说明，以及不能区分读取拒绝与无数据。
- [Supported capabilities (iOS)](https://developer.apple.com/help/account/reference/supported-capabilities-ios)：HealthKit 在ADP、ADEP、Apple Developer三列均标为支持；页面说明Apple Developer为Apple账户持有者。
- [Membership / account overview](https://developer.apple.com/support/compare-memberships/)：Personal Team 仍存在设备数量、App数量和7天签名等限制。

这些文档确认平台接入方式，不证明当前个人签名成功。仍需验证选用配置的 entitlement、授权、手表同步、查询及关联。
