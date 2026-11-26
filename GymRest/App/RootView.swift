import SwiftUI
import SwiftData

@MainActor struct AppRuntime {
    private static var cached: AppRuntime?
    static func open() throws -> AppRuntime {
        if let cached { return cached }
        let runtime = try AppRuntime()
        cached = runtime
        return runtime
    }
    let container: ModelContainer
    let store: TrainingStore
    let controller: TrainingController
    private init() throws {
        // Retain SwiftData's default store location, creating only its missing parent directory.
        _ = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        container = try ModelContainer(for: TrainingProgram.self, TrainingPlan.self, LibraryPreferences.self, ActiveTraining.self, TrainingRecord.self)
        let trainingStore = try TrainingStore(container: container)
        store = trainingStore
        let watchLink = PhoneWatchLink.shared
        watchLink.attachReceipt = { try trainingStore.attachWatchReceipt($0) }
        watchLink.trainingEnd = { try trainingStore.recordEnd(for: $0) }
        let liveActivity = TrainingLiveActivity()
        controller = try TrainingController(store: store, activitySync: { session, issue, blocked in
            if !blocked { watchLink.publish(session) }
            return await liveActivity.synchronize(session, issue: issue, blocked: blocked)
        }, prepare: {
            // Transfer reminder ownership from the technical probe to training.
            let probe = ProbeModel()
            await probe.cancel()
            if let error = probe.error {
                throw NSError(domain: "GymRest.Probe", code: 1, userInfo: [NSLocalizedDescriptionKey: error])
            }
        })
        let trainingController = controller
        watchLink.refreshTraining = { await trainingController.refreshLiveActivity() }
        watchLink.canStartRecording = { id in
            !trainingController.busy && trainingController.recoveryIssue == nil && trainingController.session?.sessionID == id && trainingController.session?.phase != .completed
        }
        watchLink.handleTrainingAction = { id, token, action in
            guard trainingController.session?.sessionID == id,
                  trainingController.session?.interactionID == token,
                  let action = TrainingQuickAction(rawValue: action), !trainingController.busy else { return CompanionFailure.wrongSession.localizedDescription }
            await trainingController.handleQuickAction(action, interactionID: token.uuidString)
            return trainingController.error
        }
        watchLink.flushReceipts()
    }
}

struct RootView: View {
    @State private var runtime: AppRuntime?
    @State private var error: String?
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if let runtime {
                LibraryView(controller: runtime.controller).modelContext(runtime.store.context)
                    .task(id: scenePhase) {
                        // System reminders keep running; only foreground state inspection needs this task.
                        guard scenePhase == .active else { return }
                        await runtime.controller.refreshLiveActivity()
                        while !Task.isCancelled {
                            await runtime.controller.reconcile()
                            do { try await Task.sleep(for: .seconds(1)) } catch { break }
                        }
                    }
            } else if let error {
                ContentUnavailableView {
                    Label("本地数据暂时无法打开", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(error + "\n请保留应用数据，不要卸载。")
                } actions: {
                    Button("重新尝试") { openStorage() }.buttonStyle(.borderedProminent)
                }
            } else { ProgressView("正在打开训练计划…") }
        }
        .tint(.orange)
        .task {
            guard runtime == nil else { return }
            await MediaStore.shared.bootstrap()
            openStorage()
        }
    }
    private func openStorage() {
        do { runtime = try AppRuntime.open(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
