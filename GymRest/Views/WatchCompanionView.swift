import SwiftUI

struct WatchRecordingCard: View {
    let session: TrainingSession
    @State private var link = PhoneWatchLink.shared
    @State private var confirmingStart = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Apple Watch记录", systemImage: "applewatch").font(.headline)
            if let status = link.latest, status.trainingID == session.sessionID {
                TimelineView(.periodic(from: .now, by: 5)) { timeline in
                    Text((link.confirmedThisLaunch && status.isFresh(at: timeline.date)) || status.phase.terminal ? status.phase.title : "手表状态待确认 · 上次：" + status.phase.title)
                        .foregroundStyle(status.phase == .running && link.confirmedThisLaunch && status.isFresh(at: timeline.date) ? Color.green : Color.secondary)
                }
            } else if let request = link.pendingStart, request.trainingID == session.sessionID, request.isFresh(at: .now) {
                Text("等待手表确认开始，尚未确认正在记录。").foregroundStyle(.secondary)
            } else { Text("尚未关联本次训练的手表记录。").foregroundStyle(.secondary) }
            if let status = link.latest, !status.phase.terminal {
                Text("记录控制只操作GymRest手表会话；组间休息不会暂停健康记录。").font(.caption).foregroundStyle(.secondary)
                if status.trainingID != session.sessionID {
                    Text("另一场GymRest手表记录尚未结束，请先保存或到手表核对。").font(.caption).foregroundStyle(.orange)
                    Button("保存上一场手表记录") { Task { await link.control(.saveRecording) } }
                } else { HStack {
                    if status.phase == .running { Button("暂停手表记录") { Task { await link.control(.pauseRecording) } } }
                    if status.phase == .paused { Button("继续手表记录") { Task { await link.control(.resumeRecording) } } }
                    Button("保存手表记录") { Task { await link.control(.saveRecording) } }
                }.buttonStyle(.bordered) }
            } else if link.latest?.trainingID == session.sessionID && link.latest?.phase == .saved {
                Text("本次手表记录已保存，可继续手机计组；需要新的手表记录时，请结束并开始新训练。").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("在Watch开始GymRest记录") { confirmingStart = true }.disabled(!PhoneWatchLink.buildEnabled || !link.installed || !link.paired)
            }
            if let watchIssue = link.latest?.issue { Text("手表：" + watchIssue).font(.caption).foregroundStyle(.orange) }
            if let issue = link.issue { Text(issue).font(.caption).foregroundStyle(.orange) }
            NavigationLink("连接状态与安装说明") { WatchCompanionView() }
        }.padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            .disabled(link.busy)
            .confirmationDialog("使用GymRest记录这次Watch训练？", isPresented: $confirmingStart, titleVisibility: .visible) {
                Button("请求手表开始") { Task { await link.startRecording(for: session) } }
            } message: { Text("如果已经开启系统体能训练或其他App记录，请继续使用原记录，避免重复。请求后需在手表确认，只有实际运行后才显示正在记录。") }
    }
}
struct WatchCompanionView: View {
    @State private var confirmingReset = false
    @State private var link = PhoneWatchLink.shared
    var body: some View {
        List {
            Section("连接状态") {
                LabeledContent("手表联动构建", value: PhoneWatchLink.buildEnabled ? "已启用" : "此构建未启用Watch联动")
                LabeledContent("iPhone与Watch配对", value: link.paired ? "已配对" : "尚未确认")
                LabeledContent("GymRest Watch App", value: link.installed ? "已安装" : "未检测到安装")
                LabeledContent("即时通信", value: link.reachable ? "可用" : "暂不可达")
                Button(link.busy ? "处理中…" : "刷新连接与待关联记录") { Task { await link.refresh() } }.disabled(link.busy)
                Button("重置连接状态") { confirmingReset = true }.disabled(link.busy)
                Text("系统设备配对和App联动是两回事。首次请打开手表GymRest；通信不可达不代表手表已停止记录。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let status = link.latest {
                Section("最近一次GymRest手表记录") {
                    Text(status.phase.title)
                    LabeledContent("最后同步", value: status.sentAt.formatted(date: .abbreviated, time: .standard))
                    if let id = status.workoutID { Text("已保存健康记录：" + id.uuidString).font(.caption).textSelection(.enabled) }
                    Text("只有已确认保存的GymRest手表记录才按训练标识关联到历史；不会按时间猜测并覆盖已有健康关联。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("首次使用") {
                Text("1. 在系统Watch App配对手表，安装同一构建的GymRest手机与手表App。")
                Text("2. 打开两端GymRest，点击刷新，确认已安装且通信可用。")
                Text("3. 手机开始训练后，在训练页请求Watch记录，在手表确认并授权健康读取与写入。")
                Text("4. 手机显示手表真实运行状态后再训练。手机结束训练会请求保存对应手表会话；断连时可在手表自行结束。")
                Text("5. 健康数据由手表写入一次，手机训练组数仍由你确认。")
            }
            Section("无Mac安装") {
                Text("需要包含Watch/GymRestWatch.app的IPA以及能处理手表签名/安装的工具；仅把手机App安装成功不足以证明手表可安装。")
                Link("WatchBridge项目与兼容说明", destination: URL(string: "https://github.com/AdminZachary/WatchBridge")!)
                Link("Apple TestFlight手表安装说明", destination: URL(string: "https://testflight.apple.com/")!)
                Text("WatchBridge为社区实验性安装工具；签名能力、个人账号和各系统版本需实际验证。不要把Apple ID密码或签名私钥交给GymRest。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let issue = link.issue { Section { Text(issue).foregroundStyle(.orange).textSelection(.enabled) } }
        }.navigationTitle("Watch连接与记录")
            .task { await link.refresh() }
            .confirmationDialog("确认重置手机的手表状态缓存？", isPresented: $confirmingReset) {
                Button("已检查手表，重置连接状态") { link.resetConnectionStatus() }
            } message: { Text("先在手表确认是否仍在记录。此操作不会停止或删除手表训练，也不删除训练历史；待关联的已保存记录仍保留。") }
    }
}
