import Foundation

enum WatchStartReminder {
    // This is a user preference gate, never a claim to detect another Watch app.
    static func shouldPrompt(enabled: Bool?, session: TrainingSession?) -> Bool {
        enabled == true && (session == nil || session?.phase == .completed)
    }
}
