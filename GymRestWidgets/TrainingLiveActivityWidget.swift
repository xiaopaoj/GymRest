import ActivityKit
import SwiftUI
import WidgetKit

private struct TrainingActivityTime: View {
    let state: TrainingActivityAttributes.ContentState
    var body: some View {
        if state.phase == "training", state.durationSeconds != nil {
            if state.effortStatus == "running", state.effortRegistered == true, let end = state.effortEnd {
                Text(timerInterval: min(Date.now, end)...end, countsDown: true).monospacedDigit().frame(width: 90)
            } else if state.effortStatus == "ready" { Text("请确认完成").font(.caption) }
            else if state.effortStatus == "paused" { Text("暂停 \(state.effortRemaining ?? 0)秒").font(.caption) }
            else { Text(state.effortStatus == nil ? "待开始" : "提醒未注册").font(.caption) }
        } else if state.phase == "resting", !state.reminderRegistered {
            Text("提醒未注册").font(.caption)
        } else if state.phase == "resting", let end = state.restEnd {
            Text(timerInterval: min(Date.now, end)...end, countsDown: true)
                .monospacedDigit().frame(width: 90).minimumScaleFactor(0.6)
        } else if state.phase == "paused" {
            Text("暂停 \(state.remaining / 60):\(String(format: "%02d", state.remaining % 60))")
                .monospacedDigit().minimumScaleFactor(0.6)
        } else {
            Text("\(min(state.completedSet + 1, state.totalSets))/\(state.totalSets) 组")
                .monospacedDigit()
        }
    }
}

private struct TrainingActivityControls: View {
    let state: TrainingActivityAttributes.ContentState
    private func action(_ action: TrainingQuickAction, title: String, icon: String) -> some View {
        Button(intent: TrainingQuickActionIntent(action, interactionID: state.interactionID)) {
            Label(title, systemImage: icon).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered).tint(.orange).font(.caption.bold())
        .accessibilityLabel(title)
    }
    var body: some View {
        if state.blocked {
            Link("打开 GymRest 恢复进度", destination: URL(string: "gymrest://training")!)
        } else if state.phase == "training" {
            if state.durationSeconds != nil {
                if state.effortStatus == nil || (state.effortStatus == "running" && state.effortRegistered != true) {
                    action(.startEffort, title: "开始计时 · " + (state.partTitle ?? "本组"), icon: "timer")
                } else if state.effortStatus == "paused" {
                    action(.resumeEffort, title: "继续动作计时", icon: "play.fill")
                } else {
                    HStack(spacing: 6) {
                        if state.effortStatus == "running" { action(.pauseEffort, title: "暂停计时", icon: "pause.fill") }
                        action(.completeSet, title: state.completionTitle ?? "到时确认完成", icon: "checkmark")
                    }
                }
            } else { action(.completeSet, title: state.completionTitle ?? "完成本组", icon: "checkmark") }
        } else if state.phase == "resting" || state.phase == "paused" {
            HStack(spacing: 6) {
                if state.phase == "resting" && !state.reminderRegistered {
                    action(.retryRest, title: "重试提醒", icon: "arrow.clockwise")
                } else if state.phase == "paused" {
                    action(.resumeRest, title: "继续", icon: "play.fill")
                } else {
                    action(.pauseRest, title: "暂停", icon: "pause.fill")
                }
                action(.addRest, title: "+15秒", icon: "plus")
                action(.finishRest, title: "结束休息", icon: "forward.end.fill")
            }
        }
    }
}

private struct TrainingActivityDetails: View {
    let state: TrainingActivityAttributes.ContentState
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(state.exerciseName, systemImage: "dumbbell.fill")
                    .font(.headline).lineLimit(2).privacySensitive()
                Spacer(minLength: 8)
                TrainingActivityTime(state: state).foregroundStyle(.orange).font(.headline)
            }
            Text(state.progressSummary ?? "\(state.planName) · 已完成 \(state.completedSet)/\(state.totalSets) 组")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).privacySensitive()
            if let issue = state.issue {
                Text(issue).font(.caption).foregroundStyle(.orange).lineLimit(2)
            } else {
                Text(state.phase == "training" ? (state.durationSeconds == nil ? "做完当前侧后确认 · " + (state.partTitle ?? "本组") : "到时提醒后确认完成 · " + (state.partTitle ?? "本组")) : (state.restTitle ?? "休息") + " · " + state.nextStep)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if state.phase == "training", let details = state.setDetails {
                Text(details).font(.caption).lineLimit(1).privacySensitive()
            }
            if let date = state.synchronizedAt {
                HStack(spacing: 4) { Text("状态同步"); Text(date, format: .dateTime.hour().minute().second()) }.font(.caption2).foregroundStyle(.secondary)
            }
            TrainingActivityControls(state: state)
        }
    }
}

struct TrainingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrainingActivityAttributes.self) { context in
            TrainingActivityDetails(state: context.state).padding(14)
                .activityBackgroundTint(.black).foregroundStyle(.white)
                .activitySystemActionForegroundColor(.orange)
                .widgetURL(URL(string: "gymrest://training")!)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    TrainingActivityDetails(state: context.state).padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.phase == "training" ? "dumbbell.fill" : "timer")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                TrainingActivityTime(state: context.state).font(.caption).foregroundStyle(.orange)
            } minimal: {
                Image(systemName: "dumbbell.fill").foregroundStyle(.orange)
            }
            .widgetURL(URL(string: "gymrest://training")!).keylineTint(.orange)
        }
    }
}
