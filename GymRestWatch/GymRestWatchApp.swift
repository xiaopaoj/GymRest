import SwiftUI
import WatchKit
import HealthKit

final class GymRestWatchDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        // Launch is a request to connect, not permission to start a stale workout.
        Task { @MainActor in await WatchWorkoutManager.shared.refresh() }
    }
    func handleActiveWorkoutRecovery() {
        Task { @MainActor in await WatchWorkoutManager.shared.recover() }
    }
}
@main struct GymRestWatchApp: App {
    @WKApplicationDelegateAdaptor(GymRestWatchDelegate.self) var delegate
    var body: some Scene { WindowGroup { WatchTrainingView() } }
}
