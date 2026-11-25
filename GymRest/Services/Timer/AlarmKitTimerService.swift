import AlarmKit
import ActivityKit
import SwiftUI

@MainActor
final class AlarmKitTimerService: TimerService {
    let name = "AlarmKit"
    var authorization: String { get async { String(describing: AlarmManager.shared.authorizationState) } }
    func authorize() async throws {
        guard try await AlarmManager.shared.requestAuthorization() == .authorized else { throw TimerFailure.denied }
    }
    func start(id: UUID, seconds: Int) async throws {
        guard AlarmManager.shared.authorizationState == .authorized else { throw TimerFailure.denied }
        // Remove all alarms belonging to this application before replacement.
        for alarm in try AlarmManager.shared.alarms { try AlarmManager.shared.cancel(id: alarm.id) }
        let presentation = AlarmPresentation(
            alert: .init(title: "休息结束", stopButton: .init(text: "停止", textColor: .white, systemImageName: "stop.fill")),
            countdown: .init(title: "组间休息"))
        let attributes = AlarmAttributes(presentation: presentation, metadata: RestMetadata(), tintColor: .orange)
        _ = try await AlarmManager.shared.schedule(id: id, configuration: .timer(duration: TimeInterval(seconds), attributes: attributes))
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
