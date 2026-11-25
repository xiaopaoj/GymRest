import SwiftUI
import UserNotifications

final class ForegroundNotifications: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

@main
struct GymRestApp: App {
    private let delegate = ForegroundNotifications()
    init() { UNUserNotificationCenter.current().delegate = delegate }
    var body: some Scene { WindowGroup { RootView() } }
}
