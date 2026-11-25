import Foundation
import Observation

@MainActor @Observable final class TrainingController {
    private let store: TrainingStore
    private let alarm: any TimerService
    private let notification: any TimerService
    private let now: () -> Date
    private let prepare: () async throws -> Void
    private var lastCompletion: Date?
    private var completionSaved = false
    private var reconciling = false
    private var revision = 0
    private var lastSyncError: String?
    private(set) var session: TrainingSession?
    private(set) var recoveryIssue: String?
    var busy = false
    var error: String?
    var permission = "尚未查询"
    var idlePhase: TrainingPhase { session?.phase ?? .idle }
    var preferences: LibraryPreferences { store.preferences }
    private var service: any TimerService { (session?.fallback ?? preferences.notificationFallback) ? notification : alarm }

    init(store: TrainingStore, alarm: any TimerService = AlarmKitTimerService(), notification: any TimerService = LocalNotificationTimerService(), now: @escaping () -> Date = Date.init, prepare: @escaping () async throws -> Void = {}) throws {
        self.store = store; self.alarm = alarm; self.notification = notification; self.now = now; self.prepare = prepare
        do { session = try store.load() }
        catch {
            // Only isolate snapshot problems. Database I/O failures must still reach the storage error screen.
            guard error is DecodingError || error is TrainingError else { throw error }
            let message = "当前训练进度暂时无法恢复，计划和历史记录仍可查看。为避免覆盖进度，暂不能开始新训练。"
            recoveryIssue = message
            self.error = message + "\n" + error.localizedDescription
        }
    }
    private func persist() throws {
        try store.save(session, at: now())
        if session?.phase == .completed { completionSaved = true }
    }
    private func perform(clearErrorOnSuccess: Bool = true, allowRecovery: Bool = false, _ action: () async throws -> Void) async {
        guard !busy else { error = "操作正在处理中，请稍后重试。"; return }
        guard allowRecovery || recoveryIssue == nil else { error = recoveryIssue; return }
        revision += 1
        if clearErrorOnSuccess { lastSyncError = nil }
        busy = true; defer { busy = false }
        do { try await action(); if clearErrorOnSuccess { error = nil } }
        catch {
            let message = error.localizedDescription + "\n" + String(reflecting: error)
            if clearErrorOnSuccess || lastSyncError != message { self.error = message }
            if !clearErrorOnSuccess { lastSyncError = message }
        }
    }
    func retryRecovery() async {
        await perform(allowRecovery: true) {
            let restored = try store.load()
            session = restored; recoveryIssue = nil
        }
    }
    func authorize() async {
        await perform(allowRecovery: true) { try await service.authorize(); permission = await service.authorization }
    }
    func start(plan: TrainingPlan) async {
        await perform {
            guard session == nil || session?.phase == .completed else { throw TrainingError.activeSession }
            let exercises = try plan.exercises()
            guard !exercises.isEmpty else { throw TrainingError.emptyPlan }
            try await prepare()
            let oldSession = session
            let oldCompletionSaved = completionSaved
            let oldLastCompletion = lastCompletion
            session = try TrainingSession(planID: plan.id, planName: plan.name, exercises: exercises, fallback: preferences.notificationFallback)
            completionSaved = false
            lastCompletion = nil
            session?.startedAt = now()
            do { try persist() } catch {
                session = oldSession; completionSaved = oldCompletionSaved; lastCompletion = oldLastCompletion
                throw error
            }
        }
    }
    private func cancelReminder() async throws {
        if let id = session?.timerID { try await service.cancel(id: id) }
    }
    private func schedule(seconds: TimeInterval) async throws {
        try await cancelReminder()
        guard var value = session else { return }
        let duration = max(1, min(86400, Int(ceil(seconds))))
        value.phase = .resting; value.timerID = UUID()
        value.remaining = Double(duration); value.restEnd = now().addingTimeInterval(Double(duration))
        value.reminderRegistered = false; session = value
        try persist() // Journal ID before system registration for crash recovery.
        try await service.start(id: value.timerID!, seconds: duration, context: value.restContext)
        // Authorization can keep the scheduling call suspended; do not retain a deadline from before the prompt.
        session?.restEnd = now().addingTimeInterval(Double(duration))
        session?.reminderRegistered = true
        try persist()
    }
    func completeSet() async {
        await perform {
            guard var value = session, value.phase == .training else { return }
            if let lastCompletion, (0..<0.5).contains(now().timeIntervalSince(lastCompletion)) { return }
            lastCompletion = now()
            guard value.completed[value.index] < value.current.sets else { return }
            if value.performedNames == nil {
                value.performedNames = value.exercises.enumerated().map { i, exercise in Array(repeating: exercise.name, count: value.completed[i]) }
            }
            let performedIndex = value.index
            let performedName = value.current.name
            value.performedNames?[performedIndex].append(performedName)
            value.completed[value.index] += 1
            let needsRest = value.completed[value.index] < value.current.sets || value.current.restAfterLastSet
            if needsRest {
                value.originalRest = value.current.rest(afterSet: value.completed[value.index])
                // Persist the manual completion exactly once, even if permission/registration fails.
                value.phase = .paused; value.remaining = Double(value.originalRest)
                session = value; try persist()
                try await schedule(seconds: Double(value.originalRest))
            } else {
                value.advanceAfterSet(); session = value; try persist()
            }
        }
    }
    func skipRest() async {
        await perform {
            guard session?.phase == .resting || session?.phase == .paused else { return }
            try await cancelReminder()
            session?.advanceAfterSet(); try persist()
        }
    }
    func pause() async {
        await perform {
            guard let value = session, value.phase == .resting else { return }
            let remaining = value.secondsLeft(at: now())
            try await cancelReminder()
            session?.phase = .paused; session?.remaining = remaining
            session?.restEnd = nil; session?.timerID = nil; session?.reminderRegistered = false
            try persist()
        }
    }
    func resume() async {
        await perform {
            guard let value = session, value.phase == .paused else { return }
            if value.remaining <= 0 { try await cancelReminder(); session?.advanceAfterSet(); try persist() }
            else { try await schedule(seconds: value.remaining) }
        }
    }
    func adjust(by seconds: Int) async {
        await perform {
            guard let value = session, value.phase == .resting || value.phase == .paused else { return }
            let duration = min(86400, max(0, value.secondsLeft(at: now()) + Double(seconds)))
            if duration <= 0 {
                try await cancelReminder(); session?.advanceAfterSet(); try persist()
            } else if value.phase == .paused {
                session?.remaining = duration; try persist()
            } else { try await schedule(seconds: duration) }
        }
    }
    func restartRest() async {
        await perform {
            guard let value = session, value.phase == .resting || value.phase == .paused else { return }
            try await schedule(seconds: Double(value.originalRest))
        }
    }
    func selectAlternative(_ id: UUID?) async {
        await perform {
            guard var value = session, value.phase == .training else { return }
            if value.originalExercises == nil { value.originalExercises = value.exercises }
            let original = value.originalExercises![value.index]
            var replacement = original
            if let id {
                guard let alternative = original.alternatives.first(where: { $0.id == id }) else { throw TrainingError.invalidExercise }
                replacement.name = alternative.name
                replacement.restSeconds = alternative.restSeconds
                replacement.restOverrides = alternative.restOverrides
            }
            // Keep the slot ID and set count; already performed set names remain immutable.
            value.exercises[value.index] = replacement
            session = value; try persist()
        }
    }
    func navigate(previous: Bool) async {
        await perform {
            guard var value = session, value.phase != .completed else { return }
            try await cancelReminder()
            value.timerID = nil; value.restEnd = nil; value.remaining = 0; value.reminderRegistered = false
            if previous {
                value.index = max(0, value.index - 1)
                value.completed[value.index] = 0
                value.performedNames?[value.index] = []
                value.phase = .training
            } else if value.index + 1 < value.exercises.count {
                value.index += 1; value.phase = .training
            } else { value.phase = .completed }
            session = value; try persist()
        }
    }
    func end() async {
        await perform {
            try await cancelReminder()
            // Only clear memory after persistent deletion succeeds.
            if completionSaved { try store.save(nil) }
            else { try store.finish(session, at: now()) }
            session = nil; completionSaved = false
        }
    }
    func reconcile() async {
        guard recoveryIssue == nil, !Task.isCancelled, !busy, !reconciling else { return }
        reconciling = true; defer { reconciling = false }
        let observedRevision = revision
        do {
            let authorization = await service.authorization
            guard !Task.isCancelled, !busy, observedRevision == revision else { return }
            permission = authorization
            guard let value = session, value.phase == .resting || value.phase == .paused, let id = value.timerID else { return }
            let inspection = try await service.inspect(id: id)
            guard !Task.isCancelled, !busy, observedRevision == revision, session?.timerID == id else { return }
            await perform(clearErrorOnSuccess: false) {
                switch inspection {
                case .running(let end):
                    if value.phase == .paused && end == nil { throw TrainingError.uncalibratedTimer }
                    session?.phase = .resting
                    session?.reminderRegistered = true
                    if let end { session?.restEnd = end }
                    if session!.secondsLeft(at: now()) <= 0 {
                        try await cancelReminder(); session?.advanceAfterSet()
                    }
                case .paused(let remaining):
                    session?.phase = .paused; session?.remaining = remaining ?? value.secondsLeft(at: now())
                    session?.restEnd = nil
                case .alerting:
                    try await cancelReminder(); session?.advanceAfterSet()
                case .missing:
                    if value.reminderRegistered && value.secondsLeft(at: now()) <= 0 { session?.advanceAfterSet() }
                    else { throw TrainingError.missingReminder }
                }
                if session != value { try persist() }
            }
        } catch {
            if observedRevision == revision, lastSyncError != error.localizedDescription {
                lastSyncError = error.localizedDescription; self.error = error.localizedDescription
            }
        }
    }
}
