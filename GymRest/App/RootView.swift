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
        store = try TrainingStore(container: container)
        let liveActivity = TrainingLiveActivity()
        controller = try TrainingController(store: store, activitySync: { session, issue, blocked in
            await liveActivity.synchronize(session, issue: issue, blocked: blocked)
        }, prepare: {
            // Transfer reminder ownership from the technical probe to training.
            let probe = ProbeModel()
            await probe.cancel()
            if let error = probe.error {
                throw NSError(domain: "GymRest.Probe", code: 1, userInfo: [NSLocalizedDescriptionKey: error])
            }
        })
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
            openStorage()
        }
    }
    private func openStorage() {
        do { runtime = try AppRuntime.open(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
