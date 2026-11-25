import Foundation
import Observation

@MainActor @Observable final class TrainingController {
    private let store: TrainingStore
    private let alarm: any TimerService
    private let notification: any TimerService
    private let now: () -> Date
    private let prepare: () async throws -> Void
    private let activitySync: @MainActor (TrainingSession?, String?, Bool) async -> String?
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
    private(set) var liveActivityIssue: String?
    var idlePhase: TrainingPhase { session?.phase ?? .idle }
    var preferences: LibraryPreferences { store.preferences }
    private var service: any TimerService { (session?.fallback ?? preferences.notificationFallback) ? notification : alarm }

    init(store: TrainingStore, alarm: any TimerService = AlarmKitTimerService(), notification: any TimerService = LocalNotificationTimerService(), now: @escaping () -> Date = Date.init,
         activitySync: @escaping @MainActor (TrainingSession?, String?, Bool) async -> String? = { _, _, _ in nil },
         prepare: @escaping () async throws -> Void = {}) throws {
        self.store = store; self.alarm = alarm; self.notification = notification; self.now = now; self.prepare = prepare
        self.activitySync = activitySync
        do {
            session = try store.load()
            if session != nil && session?.interactionID == nil {
                session?.interactionID = UUID()
                try store.save(session)
            }
        }
        catch {
            // Only isolate snapshot problems. Database I/O failures must still reach the storage error screen.
            guard error is DecodingError || error is TrainingError || error is PerformanceError else { throw error }
            let message = "当前训练进度暂时无法恢复，计划和历史记录仍可查看。为避免覆盖进度，暂不能开始新训练。"
            recoveryIssue = message
            self.error = message + "\n" + error.localizedDescription
        }
    }
    private func persist() throws {
        session?.interactionID = UUID()
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
        // Await publication before accepting another action, including a background intent.
        await publishLiveActivity()
    }
    func refreshLiveActivity() async {
        guard !busy else { return }
        await publishLiveActivity()
    }
    private func publishLiveActivity() async {
        liveActivityIssue = await activitySync(session, error, recoveryIssue != nil)
    }
    func finishRestFromAlarm(timerID: String) async {
        guard !busy else { return }
        guard recoveryIssue == nil, let id = UUID(uuidString: timerID),
              let value = session, !value.fallback, value.timerID == id,
              value.phase == .resting || value.phase == .paused else {
            await refreshLiveActivity(); return
        }
        // Stopping an alert acknowledges only the rest, never a completed training set.
        // Reuse cancellation and durable saving; a cancel error must not advance progress.
        await skipRest()
    }
    func handleQuickAction(_ action: TrainingQuickAction, interactionID: String) async {
        // No await between validating the token and entering an existing serialized action.
        // Revalidate after every asynchronous preflight because the app may act meanwhile.
        guard !busy else { return }
        guard recoveryIssue == nil else { await refreshLiveActivity(); return }
        guard let value = session, value.interactionID?.uuidString == interactionID,
              Self.allows(action, in: value.phase) else {
            await refreshLiveActivity(); return
        }
        if action != .finishRest {
            await reconcile()
            guard !busy, session?.interactionID?.uuidString == interactionID else {
                await refreshLiveActivity(); return
            }
        }
        let needsReminder: Bool
        switch action {
        case .completeSet:
            needsReminder = value.restDuration(afterSet: value.completed[value.index] + 1) != nil
        case .resumeRest: needsReminder = value.remaining > 0
        case .retryRest: needsReminder = true
        case .addRest: needsReminder = value.phase == .resting
        case .pauseRest, .finishRest: needsReminder = false
        }
        if needsReminder {
            let allowed = await service.canScheduleInBackground
            guard !busy, session?.interactionID?.uuidString == interactionID else {
                await refreshLiveActivity(); return
            }
            guard allowed else {
                error = "请先打开 App 申请提醒权限，再使用锁屏操作。本次操作未执行。"
                await refreshLiveActivity(); return
            }
        }
        switch action {
        case .completeSet: await completeSet()
        case .pauseRest: await pause()
        case .resumeRest: await resume()
        case .retryRest: await restartRest()
        case .addRest: await adjust(by: 15)
        case .finishRest: await skipRest()
        }
    }
    private static func allows(_ action: TrainingQuickAction, in phase: TrainingPhase) -> Bool {
        switch action {
        case .completeSet: phase == .training
        case .pauseRest: phase == .resting
        case .resumeRest: phase == .paused
        case .retryRest, .addRest, .finishRest: phase == .resting || phase == .paused
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
            do {
                session?.setDrafts = try exercises.map { exercise in
                    // Explicit plan fields win; fill only missing fields from matching history.
                    try store.suggestedValues(for: exercise)
                }
            } catch { session = oldSession; throw error }
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
            value.preparePerformanceStorage()
            if value.performedNames == nil {
                value.performedNames = value.exercises.enumerated().map { i, exercise in Array(repeating: exercise.name, count: value.completed[i]) }
            }
            let performedIndex = value.index
            let performedName = value.current.name
            value.performedNames?[performedIndex].append(performedName)
            let setValues = value.currentSetValues
            try setValues.validate()
            value.performances?[performedIndex].append(SetPerformance(exerciseName: performedName,
                catalogID: value.current.catalogID, values: setValues,
                profileKey: value.current.profileKey(for: setValues), completedAt: now()))
            value.completed[value.index] += 1
            if let duration = value.restDuration(afterSet: value.completed[value.index]) {
                value.originalRest = duration
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
                replacement.catalogID = alternative.catalogID
                replacement.prescription = alternative.prescription
            }
            // Keep the slot ID and set count; already performed set names remain immutable.
            value.exercises[value.index] = replacement
            value.preparePerformanceStorage()
            let planned = replacement.prescription ?? SetValues()
            let key = replacement.profileKey(for: planned)
            let inSession = value.performances?[value.index].last(where: { $0.profileKey == key })?.values
            if let inSession { value.setDrafts?[value.index] = inSession }
            else { value.setDrafts?[value.index] = try store.suggestedValues(for: replacement) }
            session = value; try persist()
        }
    }
    func setValues(_ values: SetValues, interactionID: UUID?) async {
        await perform {
            guard var value = session, value.interactionID == interactionID,
                  value.phase != .completed, value.completed[value.index] < value.current.sets else { throw PerformanceError.staleOrder }
            try values.validate()
            value.preparePerformanceStorage(); value.setDrafts?[value.index] = values
            session = value; try persist()
        }
    }
    var reorderableExercises: [ExerciseSpec] {
        guard let session, session.phase == .training else { return [] }
        return session.exercises.enumerated().filter { $0.offset >= session.index && session.completed[$0.offset] == 0 }.map(\.element)
    }
    func reorderRemaining(_ ids: [UUID], interactionID: UUID?) async {
        await perform {
            guard var value = session, value.phase == .training, value.interactionID == interactionID else { throw PerformanceError.staleOrder }
            let positions = value.exercises.indices.filter { $0 >= value.index && value.completed[$0] == 0 }
            guard ids.count == positions.count, Set(ids).count == ids.count,
                  Set(ids) == Set(positions.map { value.exercises[$0].id }) else { throw PerformanceError.staleOrder }
            let old = value
            for (destination, id) in zip(positions, ids) {
                guard let source = old.exercises.firstIndex(where: { $0.id == id }) else { throw PerformanceError.staleOrder }
                value.exercises[destination] = old.exercises[source]
                if let originals = old.originalExercises { value.originalExercises?[destination] = originals[source] }
                if let names = old.performedNames { value.performedNames?[destination] = names[source] }
                if let performances = old.performances { value.performances?[destination] = performances[source] }
                if let drafts = old.setDrafts { value.setDrafts?[destination] = drafts[source] }
            }
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
                value.performances?[value.index] = []
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
                await refreshLiveActivity()
            }
        }
    }
}
