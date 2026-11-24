import SwiftUI

struct ProbeView: View {
    @State private var model = ProbeModel()
    @State private var seconds = "90"
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            Form {
                Section("提醒能力验证 · 阶段一") {
                    Toggle("使用本地通知降级", isOn: $model.useNotification).disabled(model.busy || model.task != nil)
                    Text(model.useNotification ? "本地通知不能保证突破静音或专注模式，不提供 AlarmKit 锁屏倒计时。" : "AlarmKit 的免费签名、锁屏、灵动岛能力需要真机验证。")
                        .font(.footnote).foregroundStyle(.secondary)
                    LabeledContent("权限", value: model.permission)
                    LabeledContent("系统状态", value: model.systemStatus)
                    Button("申请当前提醒权限") { Task { await model.authorize() } }
                }
                Section("休息倒计时") {
                    if let task = model.task {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text("\(max(0, Int(ceil(task.end.timeIntervalSince(context.date))))) 秒")
                                .font(.system(size: 52, weight: .bold, design: .rounded)).monospacedDigit()
                        }
                        Text("界面按绝对时间刷新；是否仍在计时以系统状态为准。外部暂停后请取消重测。")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("ID: \(task.id.uuidString)").font(.caption).textSelection(.enabled)
                    }
                    HStack {
                        Button("30 秒") { Task { await model.start(seconds: 30) } }
                        Spacer()
                        Button("60 秒") { Task { await model.start(seconds: 60) } }
                    }.buttonStyle(.borderedProminent)
                    TextField("自定义秒数（1–86400）", text: $seconds).keyboardType(.numberPad)
                    Button("开始自定义倒计时") {
                        Task { await model.start(seconds: Int(seconds) ?? 0) }
                    }
                    Button("取消当前任务", role: .destructive) { Task { await model.cancel() } }
                    Button("刷新系统状态") { Task { await model.refresh() } }
                }.disabled(model.busy)
                if let error = model.error {
                    Section("调用错误（请保留用于排查）") { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                }
                Section("验证提示") {
                    Text("先运行 AlarmKit，再测试降级通知。切换方式前需取消任务。请分别测试锁屏、后台、终止进程、静音及专注模式，并记录实际结果。")
                }
            }
            .navigationTitle("GymRest 技术验证")
            .task { await model.refresh() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.refresh() } } }
            .onChange(of: model.useNotification) { _, _ in Task { await model.refresh() } }
        }
    }
}
