import SwiftUI

/// Foreground-only polling. No alert, no background keepalive, no workout writes.
struct HealthActivityTip: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("healthActivityTipsEnabled") private var enabled = true
    @State private var monitor = HealthActivityMonitor.shared
    private var shouldPoll: Bool { enabled && scenePhase == .active && monitor.authorizationRequested && WorkoutReader.buildEnabled }
    var body: some View {
        Group {
            if enabled {
                VStack(alignment: .leading, spacing: 6) {
                    if !WorkoutReader.buildEnabled {
                        Label("当前版本未启用健康读取 · 请手动确认手表运动", systemImage: "info.circle")
                    } else if !monitor.authorizationRequested {
                        Label("尚未读取健康数据 · 请手动确认手表运动", systemImage: "info.circle")
                        Button("允许读取近期锻炼数据") { Task { await monitor.requestAccess() } }.disabled(monitor.busy)
                    } else {
                        TimelineView(.periodic(from: .now, by: 30)) { timeline in
                            let evidence = monitor.evidence(at: timeline.date)
                            Label(monitor.issue == nil ? evidence.title : "健康数据暂时读取失败 · 暂无法判断", systemImage: "info.circle")
                            if let date = evidence.latestSampleEnd {
                                Text("最新样本结束：" + date.formatted(date: .omitted, time: .standard))
                            }
                        }
                        if let date = monitor.checkedAt {
                            Text("上次查询：" + date.formatted(date: .omitted, time: .standard)).foregroundStyle(.secondary)
                        }
                    }
                    Text("数据同步有延迟；运动迹象不代表已开启体能训练，无数据也不代表未开启。")
                        .foregroundStyle(.secondary)
                }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .task(id: shouldPoll) {
            guard shouldPoll else { return }
            while !Task.isCancelled {
                await monitor.refresh()
                do { try await Task.sleep(for: .seconds(60)) } catch { break }
            }
        }
    }
}

struct HealthActivitySettingsView: View {
    @AppStorage("healthActivityTipsEnabled") private var enabled = true
    @State private var monitor = HealthActivityMonitor.shared
    var body: some View {
        Form {
            Section {
                Toggle("训练中显示健康数据小提示", isOn: $enabled)
                Text("仅在手机训练页处于前台时每60秒查询一次近期锻炼数据，不需要安装GymRest手表App。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("近期运动迹象 · 试验功能") {
                HealthActivityTip()
                Button(monitor.busy ? "正在读取…" : "请求健康读取权限并查询") { Task { await monitor.requestAccess() } }
                    .disabled(monitor.busy || !WorkoutReader.buildEnabled)
                Button("刷新健康数据") { Task { await monitor.refresh() } }
                    .disabled(monitor.busy || !monitor.authorizationRequested || !WorkoutReader.buildEnabled)
                Text("读取最近15分钟、来源型号标注为Watch的非手动锻炼样本；3分钟内的新样本仅作为近期运动迹象。阈值为试验规则，尚未经过真机校准。快走也会累计锻炼分钟，力量训练开启后也可能没有新样本。")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("空结果可能来自未授权、尚未同步或未产生锻炼分钟，无法区分。请在系统健康权限中检查“锻炼分钟数”；本App不会写入健康数据。")
                    .font(.footnote).foregroundStyle(.secondary)
                if let issue = monitor.issue { Text(issue).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            }
        }.navigationTitle("健康数据辅助判断")
    }
}
