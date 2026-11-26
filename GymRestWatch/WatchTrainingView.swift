import SwiftUI

struct WatchTrainingView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var manager = WatchWorkoutManager.shared
    @State private var confirmingEnd = false
    @State private var confirmingDiscard = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Label(manager.transport.reachable ? "手机已连接" : "手机暂不可达", systemImage: manager.transport.reachable ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                        .font(.caption).foregroundStyle(.secondary)
                    if let status = manager.status {
                        Text(status.phase.title).font(.headline).foregroundStyle(status.phase == .running ? .green : .orange)
                        if let start = status.start, !status.phase.terminal {
                            Text(start, style: .timer).font(.title2.monospacedDigit())
                        }
                        HStack {
                            Text(manager.heartRate.map { "\(Int($0)) 次/分" } ?? "心率 —")
                            Spacer()
                            Text(manager.energy.map { "\(Int($0)) 千卡" } ?? "能量 —")
                        }.font(.caption)
                        recordingControls(status)
                    }
                    if manager.needsRecovery { Text("上次记录等待恢复确认，暂不宣称正在采集。").font(.footnote).foregroundStyle(.orange) }
                    if manager.canStart && !manager.unlinkedRecovery {
                        Text("请先结束系统体能训练或其他App的记录，再开启GymRest，避免重复记录。")
                            .font(.caption).foregroundStyle(.secondary)
                        if let request = manager.startRequest, request.isFresh(at: .now) {
                            Text("手机请求：" + request.title).font(.headline)
                            Button("开始GymRest力量训练") { Task { await manager.startPending() } }.buttonStyle(.borderedProminent)
                        } else if manager.phone != nil {
                            Button("关联手机训练并请求开始") { Task { await manager.requestRecording() } }
                        } else { Text("请先在iPhone开始GymRest训练，再刷新连接。").font(.footnote) }
                    }
                    if let phone = manager.phone {
                        TimelineView(.periodic(from: .now, by: 5)) { timeline in phoneControls(phone, now: timeline.date) }
                    }
                    if let issue = manager.issue { Text(issue).font(.caption).foregroundStyle(.orange) }
                    Button("刷新手机连接") { Task { await manager.refresh() } }
                    if manager.needsRecovery { Button("尝试恢复手表记录") { Task { await manager.recover() } } }
                    if manager.unlinkedRecovery {
                        Button("恢复系统中的GymRest记录") { Task { await manager.recover() } }
                        Button("丢弃无法关联的记录", role: .destructive) { confirmingDiscard = true }
                    }
                    Text("组数仅在你确认后增加。手表记录暂停与手机组间休息是独立操作。")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(.horizontal, 4)
            }.navigationTitle("GymRest")
                .disabled(manager.busy)
                .task(id: scenePhase) { if scenePhase == .active { await manager.refresh() } }
                .confirmationDialog("结束并保存手表记录？", isPresented: $confirmingEnd) {
                    Button("结束并保存") { Task { await manager.finish(save: true) } }
                } message: { Text("只结束手表健康记录，不跳过或完成手机训练组。") }
                .confirmationDialog("丢弃手表记录？", isPresented: $confirmingDiscard) {
                    Button("丢弃", role: .destructive) {
                        if manager.unlinkedRecovery { manager.discardUnlinkedRecovery() }
                        else { Task { await manager.finish(save: false) } }
                    }
                } message: { Text("这份手表健康记录不再保存，手机计划和已确认组数保留。") }
        }
    }
    @ViewBuilder private func recordingControls(_ status: WatchWorkoutStatus) -> some View {
        if !status.phase.terminal {
            if status.phase == .running { Button("暂停手表记录") { manager.pause() } }
            if status.phase == .paused { Button("继续手表记录") { manager.resume() } }
            Button(status.phase == .ending ? "重试保存" : "结束并保存记录") { confirmingEnd = true }
            Button("丢弃记录", role: .destructive) { confirmingDiscard = true }
        }
    }
    @ViewBuilder private func phoneControls(_ phone: PhoneTrainingSnapshot, now: Date) -> some View {
        Divider()
        Text(phone.exercise).font(.headline)
        Text("累计 \(phone.completedSets)/\(phone.totalSets) 组 · " + phone.part).font(.caption)
        Text(phone.values).font(.caption)
        if !phone.isFresh(at: now) { Text("显示上次手机进度，请刷新后操作。").font(.caption).foregroundStyle(.orange) }
        Group {
            if phone.phase == "training" {
                if phone.durationSeconds != nil {
                    if phone.effortStatus == nil || (phone.effortStatus == "running" && !phone.effortRegistered) { action("开始动作计时", "startEffort") }
                    else if phone.effortStatus == "paused" { action("继续动作计时", "resumeEffort") }
                    else {
                        if let end = phone.effortEnd { Text(timerInterval: min(Date.now, end)...end, countsDown: true).font(.title.monospacedDigit()) }
                        if phone.effortStatus == "running" { action("暂停动作计时", "pauseEffort") }
                        action(phone.completionTitle, "completeSet")
                    }
                } else { action(phone.completionTitle, "completeSet") }
            } else if phone.phase == "resting" || phone.phase == "paused" {
                if let end = phone.restEnd { Text(timerInterval: min(Date.now, end)...end, countsDown: true).font(.title.monospacedDigit()) }
                else { Text("剩余 \(phone.remaining) 秒").monospacedDigit() }
                action(phone.phase == "paused" ? "继续休息" : "暂停休息", phone.phase == "paused" ? "resumeRest" : "pauseRest")
                action("休息＋15秒", "addRest")
                action("结束休息", "finishRest")
            }
        }.disabled(!manager.transport.reachable || !phone.isFresh(at: now))
    }
    private func action(_ title: String, _ value: String) -> some View {
        Button(title) { Task { await manager.trainingAction(value) } }.buttonStyle(.bordered)
    }
}
