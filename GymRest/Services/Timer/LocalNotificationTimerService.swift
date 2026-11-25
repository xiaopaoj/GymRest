import Foundation
import UserNotifications

@MainActor
final class LocalNotificationTimerService: TimerService {
    let name = "本地通知（降级）"
    private let center = UNUserNotificationCenter.current()
    var authorization: String { get async { String(describing: await center.notificationSettings().authorizationStatus) } }
    func authorize() async throws {
        guard try await center.requestAuthorization(options: [.alert, .sound]) else { throw TimerFailure.denied }
    }
    func start(id: UUID, seconds: Int, context: RestContext?) async throws {
        if await center.notificationSettings().authorizationStatus == .notDetermined { try await authorize() }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { throw TimerFailure.denied }
        center.removeAllPendingNotificationRequests()
        let content = UNMutableNotificationContent()
        content.title = "休息结束"
        content.body = context?.nextStep ?? "可以开始下一组训练。"
        content.sound = .default
        try await center.add(UNNotificationRequest(identifier: id.uuidString, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)))
    }
    func cancel(id: UUID) async throws {
        center.removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        center.removeDeliveredNotifications(withIdentifiers: [id.uuidString])
    }
    func inspect(id: UUID) async throws -> TimerInspection {
        let pending = await center.pendingNotificationRequests()
        guard let request = pending.first(where: { $0.identifier == id.uuidString }) else { return .missing }
        let trigger = request.trigger as? UNTimeIntervalNotificationTrigger
        return .running(end: trigger?.nextTriggerDate())
    }
    func status(id: UUID) async throws -> String {
        let pending = await center.pendingNotificationRequests()
        return pending.contains(where: { $0.identifier == id.uuidString }) ? "通知已注册" : "无待发送通知（不代表已响铃）"
    }
}
