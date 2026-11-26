import ActivityKit
import AppIntents
import Foundation

enum TrainingQuickAction: String, AppEnum {
    case completeSet, pauseRest, resumeRest, retryRest, addRest, finishRest, startEffort, pauseEffort, resumeEffort
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "训练操作" }
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] { [
        .startEffort: "开始动作计时", .pauseEffort: "暂停动作计时", .resumeEffort: "继续动作计时",
        .completeSet: "完成本组", .pauseRest: "暂停休息", .resumeRest: "继续休息",
        .retryRest: "重试提醒", .addRest: "增加15秒", .finishRest: "结束休息"
    ] }
}

struct TrainingActivityAttributes: ActivityAttributes, Sendable {
    let sessionID: String
    struct ContentState: Codable, Hashable, Sendable {
        let interactionID: String
        let planName: String
        let exerciseName: String
        let phase: String
        let completedSet: Int
        let totalSets: Int
        let nextStep: String
        let restEnd: Date?
        let remaining: Int
        let reminderRegistered: Bool
        var issue: String?
        var blocked: Bool
        var restTitle: String? = nil
        var setDetails: String? = nil
        var progressSummary: String? = nil
        var synchronizedAt: Date? = nil
        var durationSeconds: Int? = nil
        var effortStatus: String? = nil
        var effortEnd: Date? = nil
        var effortRemaining: Int? = nil
        var effortRegistered: Bool? = nil
        var partTitle: String? = nil
        var completionTitle: String? = nil
    }
}

// LiveActivityIntent executes in the app process, so it can use the existing private
// SwiftData store. The extension receives only ActivityKit content, never a second store.
struct TrainingQuickActionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "操作当前训练" }
    static var openAppWhenRun: Bool { false }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "操作") var action: TrainingQuickAction
    @Parameter(title: "进度标识") var interactionID: String

    init() {}
    init(_ action: TrainingQuickAction, interactionID: String) {
        self.action = action; self.interactionID = interactionID
    }

    @MainActor func perform() async throws -> some IntentResult {
        #if GYMREST_APP
        do {
            let runtime = try AppRuntime.open()
            await runtime.controller.handleQuickAction(action, interactionID: interactionID)
        } catch {
            await TrainingLiveActivity.reportStorageFailure()
        }
        #endif
        return .result()
    }
}

// AlarmKit stops its alarm itself, then runs this additional action. Match the exact
// registration ID so a delayed stop cannot affect a new rest or effort timer.
// Effort dismissal only marks the timer ready; it never completes a side or set.
struct RestFinishedIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "确认当前计时提醒" }
    static var openAppWhenRun: Bool { false }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "提醒标识") var timerID: String
    init() {}
    init(timerID: String) { self.timerID = timerID }

    @MainActor func perform() async throws -> some IntentResult {
        #if GYMREST_APP
        do {
            let runtime = try AppRuntime.open()
            await runtime.controller.finishRestFromAlarm(timerID: timerID)
        } catch {
            await TrainingLiveActivity.reportStorageFailure()
        }
        #endif
        return .result()
    }
}
