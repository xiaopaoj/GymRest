import SwiftUI
import SwiftData

@MainActor struct AppRuntime {
    let container: ModelContainer
    let store: TrainingStore
    let controller: TrainingController
    init() throws {
        container = try ModelContainer(for: TrainingPlan.self, LibraryPreferences.self, ActiveTraining.self)
        store = try TrainingStore(container: container)
        controller = try TrainingController(store: store, prepare: {
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
                    .task {
                        // UI reconciliation never completes a training set; the system owns the reminder.
                        while !Task.isCancelled {
                            if scenePhase == .active { await runtime.controller.reconcile() }
                            do { try await Task.sleep(for: .seconds(1)) } catch { break }
                        }
                    }
            } else if let error {
                ContentUnavailableView("本地数据暂时无法打开", systemImage: "externaldrive.badge.exclamationmark", description: Text(error + "\n请保留应用数据，不要卸载。"))
            } else { ProgressView("正在打开训练计划…") }
        }
        .tint(.orange)
        .task {
            guard runtime == nil else { return }
            do { runtime = try AppRuntime() } catch { self.error = error.localizedDescription }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, let runtime { Task { await runtime.controller.reconcile() } }
        }
    }
}
