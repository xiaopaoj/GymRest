import ActivityKit
import AppIntents
import Foundation

enum TrainingQuickAction: String, AppEnum {
    case completeSet, pauseRest, resumeRest, retryRest, addRest, finishRest
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "训练操作" }
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] { [
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
// registration ID so a delayed stop from an older rest cannot advance the new rest.
struct RestFinishedIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "结束当前组间休息" }
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
