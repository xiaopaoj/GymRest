import AlarmKit
import ActivityKit
import SwiftUI

@MainActor
final class AlarmKitTimerService: TimerService {
    let name = "AlarmKit"
    var canScheduleInBackground: Bool {
        get async { AlarmManager.shared.authorizationState == .authorized }
    }
    var authorization: String {
        get async {
            switch AlarmManager.shared.authorizationState {
            case .notDetermined: return "尚未申请"
            case .denied: return "已拒绝，请到系统设置开启"
            case .authorized: return "已授权"
            @unknown default: return "未知状态"
            }
        }
    }
    func authorize() async throws {
        guard try await AlarmManager.shared.requestAuthorization() == .authorized else { throw TimerFailure.denied }
    }
    func start(id: UUID, seconds: Int, context: RestContext?) async throws {
        if AlarmManager.shared.authorizationState == .notDetermined { try await authorize() }
        guard AlarmManager.shared.authorizationState == .authorized else { throw TimerFailure.denied }
        // Remove all alarms belonging to this application before replacement.
        for alarm in try AlarmManager.shared.alarms { try AlarmManager.shared.cancel(id: alarm.id) }
        let isEffort = context?.kind == "effort"
        let isTransition = context?.kind == "transition"
        let presentation = AlarmPresentation(
            alert: .init(title: isEffort ? "动作计时结束" : isTransition ? "动作间休息结束" : "休息结束", stopButton: .init(text: context == nil ? "停止" : isEffort ? "知道了" : "结束休息", textColor: .white, systemImageName: "stop.fill")),
            countdown: .init(title: isEffort ? "动作计时" : isTransition ? "动作间休息" : "组间休息"))
        let attributes = AlarmAttributes(presentation: presentation, metadata: RestMetadata(label: isEffort ? "动作计时" : isTransition ? "动作间休息" : "组间休息", context: context), tintColor: .orange)
        _ = try await AlarmManager.shared.schedule(id: id, configuration: .timer(
            duration: TimeInterval(seconds), attributes: attributes,
            stopIntent: context == nil ? nil : RestFinishedIntent(timerID: id.uuidString)))
    }
    func cancel(id: UUID) async throws {
        if try AlarmManager.shared.alarms.contains(where: { $0.id == id }) {
            try AlarmManager.shared.cancel(id: id)
        }
    }
    func inspect(id: UUID) async throws -> TimerInspection {
        guard let alarm = try AlarmManager.shared.alarms.first(where: { $0.id == id }) else { return .missing }
        if alarm.state == .alerting { return .alerting }
        if let activity = Activity<AlarmAttributes<RestMetadata>>.activities.first(where: { $0.content.state.alarmID == id }) {
            switch activity.content.state.mode {
            case .countdown(let value): return .running(end: value.fireDate)
            case .paused(let value): return .paused(remaining: max(0, value.totalCountdownDuration - value.previouslyElapsedDuration))
            case .alert: return .alerting
            @unknown default: break
            }
        }
        if alarm.state == .paused { return .paused(remaining: nil) }
        return .running(end: nil)
    }
    func status(id: UUID) async throws -> String {
        guard let alarm = try AlarmManager.shared.alarms.first(where: { $0.id == id }) else { return "系统中无此任务（已停止或已取消）" }
        return String(describing: alarm.state)
    }
}
