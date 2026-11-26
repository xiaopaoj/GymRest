import ActivityKit
import Foundation

@MainActor final class TrainingLiveActivity {
    private var pending: Task<String?, Never>?
    func synchronize(_ session: TrainingSession?, issue: String?, blocked: Bool) async -> String? {
        // ActivityKit updates suspend. Preserve publication order across scene changes,
        // intent execution, and foreground reconciliation instead of racing two requests.
        let previous = pending
        let task = Task { @MainActor in
            _ = await previous?.value
            return await self.apply(session, issue: issue, blocked: blocked)
        }
        pending = task
        return await task.value
    }
    private func apply(_ session: TrainingSession?, issue: String?, blocked: Bool) async -> String? {
        let activities = Activity<TrainingActivityAttributes>.activities
        guard let session, session.phase != .completed, let id = session.sessionID,
              let interactionID = session.interactionID else {
            // A corrupt active snapshot must not leave actionable stale buttons behind.
            if blocked { await Self.reportStorageFailure(); return "请先在 App 中恢复当前训练。" }
            for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }
            return nil
        }
        let state = TrainingActivityAttributes.ContentState(
            interactionID: interactionID.uuidString, planName: session.planName,
            exerciseName: session.current.name, phase: session.phase.rawValue,
            completedSet: session.completed[session.index], totalSets: session.current.sets,
            nextStep: session.restContext.nextStep, restEnd: session.restEnd,
            remaining: Int(ceil(session.remaining)), reminderRegistered: session.reminderRegistered,
            issue: issue.map { String($0.prefix(160)) }, blocked: blocked,
            restTitle: session.isTransitionRest ? "动作间休息" : "组间休息",
            setDetails: session.currentSetValues.summary,
            progressSummary: "已确认完成 \(session.completedSets)/\(session.totalSets) 组 · " + (session.phase == .training ? "第 \(session.completed[session.index] + 1) 组 · " + session.partTitle : session.phase == .paused ? "休息暂停" : "休息中"),
            synchronizedAt: Date(), durationSeconds: session.currentSetValues.durationSeconds,
            effortStatus: session.effortTimer?.status.rawValue, effortEnd: session.effortTimer?.end,
            effortRemaining: session.effortTimer.map { Int(ceil($0.remaining)) },
            effortRegistered: session.effortTimer?.registered, partTitle: session.partTitle,
            completionTitle: session.completionTitle)
        let content = ActivityContent(state: state, staleDate: session.effortTimer?.end ?? session.restEnd)
        var current: Activity<TrainingActivityAttributes>?
        for activity in activities {
            if activity.attributes.sessionID == id.uuidString,
               activity.activityState == .active || activity.activityState == .stale,
               current == nil {
                current = activity
            } else { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        if let current {
            if current.content.state != state { await current.update(content) }
            return nil
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return "系统实时活动已关闭，仍可在 App 内操作训练。"
        }
        do {
            _ = try Activity.request(attributes: TrainingActivityAttributes(sessionID: id.uuidString), content: content, pushType: nil)
            return nil
        } catch { return "锁屏训练卡片暂未显示，请在 App 内继续：" + error.localizedDescription }
    }

    static func reportStorageFailure() async {
        for activity in Activity<TrainingActivityAttributes>.activities {
            var state = activity.content.state
            state.blocked = true
            state.issue = "无法读取训练进度，请打开 App 重试。请勿卸载应用。"
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }
}
