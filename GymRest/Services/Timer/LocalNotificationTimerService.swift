import Foundation
import UserNotifications

@MainActor
final class LocalNotificationTimerService: TimerService {
    let name = "本地通知（降级）"
    private let center = UNUserNotificationCenter.current()
    var authorization: String {
        get async {
            switch await center.notificationSettings().authorizationStatus {
            case .notDetermined: return "尚未申请"
            case .denied: return "已拒绝，请到系统设置开启"
            case .authorized: return "已授权"
            case .provisional: return "临时授权（安静投递）"
            case .ephemeral: return "短时授权"
            @unknown default: return "未知状态"
            }
        }
    }
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
        // A relative trigger is not an absolute clock. Keep the persisted registration deadline;
        // repeatedly deriving a date from a relative interval can extend the visible countdown.
        return .running(end: Self.absoluteDeadline(for: request.trigger))
    }
    static func absoluteDeadline(for trigger: UNNotificationTrigger?) -> Date? {
        (trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
    }
    func status(id: UUID) async throws -> String {
        let pending = await center.pendingNotificationRequests()
        return pending.contains(where: { $0.identifier == id.uuidString }) ? "通知已注册" : "无待发送通知（不代表已响铃）"
    }
}
