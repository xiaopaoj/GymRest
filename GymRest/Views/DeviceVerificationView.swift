import SwiftUI
import UIKit
import ActivityKit

struct DeviceVerificationView: View {
    @Bindable var controller: TrainingController
    @State private var checked: Set<String> = []
    @State private var watch = ""
    @State private var watchOS = ""
    @State private var notes = ""
    @State private var savedAt: Date?
    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "未知") (\(info["CFBundleVersion"] as? String ?? "未知"))"
    }
    private var storageKey: String { "GymRest.device-verification." + version }
    private let scenarios: [(id: String, title: String, detail: String)] = [
        ("watch-install", "GymRest Watch安装与通信", "打开两端App，连接页确认已配对、已安装；刷新后手表显示当前训练。系统配对本身由Watch App完成。"),
        ("watch-start", "手表授权与真实运行状态", "手机开始训练后请求Watch记录，在手表确认并授权。唤起成功不算通过，需看到实际运行状态及健康数据。"),
        ("watch-actions", "手表计组与双侧计时", "从Watch开始每侧短计时并确认；两侧才加1组。重复旧按钮不多计组，休息暂停不暂停健康记录。"),
        ("watch-end", "手机结束后保存且不重复", "手机结束训练，核对Watch实际停止、健康App只保存一份、历史按训练标识自动关联。手动取消关联后重复同步不恢复旧关联。"),
        ("watch-offline", "断连保存与恢复", "记录中断开连接，确认Watch继续记录；手机结束后重连，核对结束请求只作用原会话、记录回传及保存失败可重试。"),
        ("health-sync", "手表训练已同步到健康App", "先在Watch完成一次训练，再确认iPhone健康App里能看到同一时间段。"),
        ("health-query", "GymRest查询到同一条运动", "进入训练记录详情，主动授权查询；核对时间、来源与设备，手动关联。空结果不能直接判断为拒绝授权。"),
        ("foreground", "前台完成组并进入休息", "新建含至少2组的测试动作，设10秒休息；完成一组后确认累计组数只加1。"),
        ("background", "切换其他App后收到提醒", "启动休息后切换App，确认系统提醒到达；时间到本身不自动完成下一训练组。"),
        ("lock-controls", "锁屏暂停/继续/加时/结束休息正常", "逐项操作并查看组数、倒计时和状态同步时间；每次确认的是同一训练。"),
        ("duplicate", "快速重复完成不会多计组", "从锁屏快速重复点完成，核对累计组数只增加1，休息提醒只保留一个。"),
        ("restore", "进程退出后进度与提醒恢复", "休息中结束进程再重新打开，确认同一动作、组数和系统提醒；不要因此重复开始训练。"),
        ("settings", "静音/专注与重签后分别复验", "分别记录声音、振动、锁屏卡片和操作结果；SideStore续签后再测一次。")
    ]
    private var report: String {
        let results = scenarios.map { "\(checked.contains($0.id) ? "已人工核对" : "待验证")：\($0.title)" }.joined(separator: "\n")
        return "GymRest真机验收（用户手动记录）\n版本：\(version)\niPhone系统：\(UIDevice.current.systemVersion)\nWatch：\(watch) / watchOS \(watchOS)\n手机HealthKit：\(WorkoutReader.buildEnabled ? "启用，只读" : "未启用")\nWatch联动构建：\(PhoneWatchLink.buildEnabled ? "启用，手表可单独授权写入" : "未启用")\n实时活动系统开关：\(ActivityAuthorizationInfo().areActivitiesEnabled ? "允许" : "关闭")\n\(results)\n备注：\(notes)"
    }
    var body: some View {
        Form {
            Section("当前环境") {
                LabeledContent("GymRest", value: version)
                LabeledContent("iPhone系统", value: UIDevice.current.systemVersion)
                LabeledContent("HealthKit构建", value: WorkoutReader.buildEnabled ? "启用，只读" : "未启用")
                LabeledContent("Watch联动构建", value: PhoneWatchLink.buildEnabled ? "已启用" : "未启用")
                LabeledContent("系统实时活动", value: ActivityAuthorizationInfo().areActivitiesEnabled ? "允许" : "关闭")
                Text("构建启用不等于签名或读取权限已验证。健康数据需在记录详情主动查询；本页不会写入运动或自动发起训练；GymRest Watch需在手表单独确认授权，记录由手表写入。")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("Watch型号", text: $watch)
                TextField("watchOS版本", text: $watchOS)
            }
            if let session = controller.session {
                Section("当前训练对照") {
                    Text(session.current.name)
                    LabeledContent("累计已完成", value: "\(session.completedSets)/\(session.totalSets)组")
                    LabeledContent("系统提醒注册", value: session.reminderRegistered ? "已注册" : "未注册或已结束")
                    if let issue = controller.liveActivityIssue { Text(issue).foregroundStyle(.orange) }
                    Text("注册成功不代表已实际听到提醒，请按下方步骤核对。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("人工验收 · \(checked.count)/\(scenarios.count)") {
                Text("只有亲自完成并核对结果后才勾选；勾选不是App自动测得的通过结果。不同App版本分别保存验收记录。")
                    .font(.footnote).foregroundStyle(.secondary)
                ForEach(scenarios, id: \.id) { scenario in
                    VStack(alignment: .leading, spacing: 5) {
                        Toggle(scenario.title, isOn: Binding(get: { checked.contains(scenario.id) }, set: { value in
                            if value { checked.insert(scenario.id) } else { checked.remove(scenario.id) }
                        }))
                        Text(scenario.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                NavigationLink("打开记录核对健康候选") { HistoryView() }
            }
            Section("结果") {
                TextField("机型、实际表现或错误原文", text: $notes, axis: .vertical)
                if let savedAt { Text("本地记录：" + savedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption) }
                Button("保存本机验收记录") { save() }
                ShareLink("导出人工验收记录", item: report)
            }
        }
        .navigationTitle("Watch与锁屏验收")
        .onAppear { load() }
        .onDisappear { save() }
    }
    private func load() {
        let value = UserDefaults.standard.dictionary(forKey: storageKey) ?? [:]
        checked = Set(value["checked"] as? [String] ?? []).intersection(Set(scenarios.map(\.id)))
        watch = value["watch"] as? String ?? ""; watchOS = value["watchOS"] as? String ?? ""
        notes = value["notes"] as? String ?? ""; savedAt = value["savedAt"] as? Date
    }
    private func save() {
        savedAt = Date()
        UserDefaults.standard.set(["checked":Array(checked),"watch":watch,"watchOS":watchOS,"notes":notes,"savedAt":Date()] as [String: Any], forKey: storageKey)
    }
}
