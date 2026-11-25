import XCTest
import SwiftData
@testable import GymRest

@MainActor final class ReviewRegressionTests: XCTestCase {
    private func store() throws -> TrainingStore {
        let container = try ModelContainer(for: TrainingProgram.self, TrainingPlan.self, LibraryPreferences.self, ActiveTraining.self, TrainingRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return try TrainingStore(container: container)
    }
    private func day(in store: TrainingStore) throws -> TrainingPlan {
        let day = try TrainingPlan(name: "测试训练", position: 10, exercises: [ExerciseSpec(name: "卧推", sets: 3)])
        store.context.insert(day); try store.context.save(); return day
    }
    func testInvalidExerciseEditKeepsSavedData() throws {
        let store = try store(); let day = try day(in: store); let original = day.exerciseData
        XCTAssertThrowsError(try PlanEditing.save([ExerciseSpec(name: "无效", restSeconds: 0)], to: day, context: store.context))
        XCTAssertEqual(day.exerciseData, original)
    }
    func testFailedExerciseCommitRollsBackAndRetainsDraftValue() throws {
        let store = try store(); let day = try day(in: store); let original = day.exerciseData
        let draft = [ExerciseSpec(name: "哑铃卧推", restSeconds: 120)]
        XCTAssertThrowsError(try PlanEditing.save(draft, to: day, context: store.context, beforeCommit: { throw TimerFailure.denied }))
        XCTAssertEqual(day.exerciseData, original)
        XCTAssertEqual(draft[0].name, "哑铃卧推")
        XCTAssertFalse(store.context.hasChanges)
    }
    func testFailedExerciseEditCanRetryWithoutSavingTheFailedDraft() throws {
        let store = try store(); let day = try day(in: store)
        let original = try day.exercises()
        let failedDraft = [ExerciseSpec(name: "不应保存的动作", restSeconds: 120)]
        XCTAssertThrowsError(try PlanEditing.save(failedDraft, to: day, context: store.context, beforeCommit: { throw TimerFailure.denied }))
        XCTAssertEqual(try day.exercises(), original)
        XCTAssertFalse(store.context.hasChanges)
        let retry = [ExerciseSpec(name: "重试后的动作", restSeconds: 47)]
        try PlanEditing.save(retry, to: day, context: store.context)
        let independent = ModelContext(store.context.container)
        let restored = try XCTUnwrap(independent.fetch(FetchDescriptor<TrainingPlan>()).first { $0.id == day.id })
        XCTAssertEqual(try restored.exercises(), retry)
        XCTAssertFalse(try restored.exercises().contains { $0.name == "不应保存的动作" })
    }
    func testValidExerciseCommitCanBeReadBack() throws {
        let store = try store(); let day = try day(in: store)
        let values = [ExerciseSpec(name: "哑铃卧推", sets: 4, restSeconds: 120)]
        try PlanEditing.save(values, to: day, context: store.context)
        XCTAssertEqual(try day.exercises(), values)
        XCTAssertFalse(store.context.hasChanges)
    }
    func testDuplicateProgramRebuildsAllIDsAndKeepsRestOptions() throws {
        let store = try store(); let context = store.context
        let parent = TrainingProgram(name: "我的五分化", position: 10); context.insert(parent)
        let option = ExerciseAlternative(name: "哑铃卧推", restSeconds: 90)
        let exercise = ExerciseSpec(name: "卧推", sets: 4, restSeconds: 120, restOverrides: [2: 150], alternatives: [option])
        let original = try TrainingPlan(name: "周一", position: 0, exercises: [exercise])
        original.programID = parent.id; context.insert(original); try context.save()
        try ProgramLibrary.duplicate(parent, context: context)
        let copy = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingProgram>()).first { $0.name == "我的五分化 副本" })
        XCTAssertNotEqual(copy.id, parent.id)
        let copiedDay = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingPlan>()).first { $0.programID == copy.id })
        XCTAssertNotEqual(copiedDay.id, original.id)
        let copiedExercise = try XCTUnwrap(copiedDay.exercises().first)
        XCTAssertNotEqual(copiedExercise.id, exercise.id)
        XCTAssertNotEqual(copiedExercise.alternatives.first?.id, option.id)
        XCTAssertEqual(copiedExercise.restOverrides, [2: 150])
        XCTAssertEqual(copiedExercise.alternatives.first?.restSeconds, 90)
        XCTAssertEqual(try original.exercises(), [exercise])
    }
    func testDuplicateEmptyProgramDoesNotInventTrainingDays() throws {
        let store = try store(); let context = store.context
        let parent = TrainingProgram(name: "空计划", position: 10); context.insert(parent); try context.save()
        try ProgramLibrary.duplicate(parent, context: context)
        let copy = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingProgram>()).first { $0.name == "空计划 副本" })
        XCTAssertFalse(try context.fetch(FetchDescriptor<TrainingPlan>()).contains { $0.programID == copy.id })
    }
    func testDanglingGroupReferenceCannotPartiallyImport() throws {
        let store = try store(); let context = store.context
        let before = try context.fetch(FetchDescriptor<TrainingPlan>()).count
        let archive = PlanArchive(version: 2, plans: [.init(id: UUID(), name: "周一", exercises: [], programID: UUID())], programs: [])
        XCTAssertThrowsError(try archive.append(to: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<TrainingPlan>()).count, before)
    }
    func testOldSystemReplyCannotFinishReplacedRestTimer() async throws {
        let store = try store(); let day = try day(in: store); let timer = MockTimerService()
        let controller = try TrainingController(store: store, alarm: timer, notification: timer)
        await controller.start(plan: day); await controller.completeSet()
        let oldID = controller.session?.timerID
        var continuation: CheckedContinuation<TimerInspection, Never>?
        timer.onInspection = { _ in await withCheckedContinuation { continuation = $0 } }
        let background = Task { await controller.reconcile() }
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        guard let resume = continuation else { background.cancel(); XCTFail("Inspection did not begin"); return }
        await controller.restartRest()
        let replacement = controller.session?.timerID
        XCTAssertNotEqual(oldID, replacement)
        resume.resume(returning: .alerting); await background.value
        XCTAssertEqual(controller.session?.timerID, replacement)
        XCTAssertEqual(controller.session?.phase, .resting)
        XCTAssertEqual(controller.session?.completedSets, 1)
        XCTAssertEqual(timer.ids.count, 1)
    }
    func testDismissedIdenticalSyncErrorIsNotReportedEverySecond() async throws {
        let store = try store(); let day = try day(in: store); let timer = MockTimerService()
        let controller = try TrainingController(store: store, alarm: timer, notification: timer)
        await controller.start(plan: day); await controller.completeSet()
        timer.inspection = .missing
        await controller.reconcile(); XCTAssertNotNil(controller.error)
        controller.error = nil
        await controller.reconcile(); XCTAssertNil(controller.error)
        XCTAssertEqual(controller.session?.phase, .resting)
    }
    func testZeroSecondSystemPauseCancelsBeforeAdvancing() async throws {
        let store = try store(); let day = try day(in: store); let timer = MockTimerService()
        let controller = try TrainingController(store: store, alarm: timer, notification: timer)
        await controller.start(plan: day); await controller.completeSet()
        timer.inspection = .paused(remaining: 0)
        await controller.reconcile()
        XCTAssertEqual(controller.session?.phase, .paused)
        XCTAssertFalse(timer.ids.isEmpty)
        await controller.resume()
        XCTAssertTrue(timer.ids.isEmpty)
        XCTAssertNil(controller.session?.timerID)
        XCTAssertEqual(controller.session?.phase, .training)
    }
    func testExternallyResumedTimerUsesSystemDeadline() async throws {
        let store = try store(); let day = try day(in: store); let timer = MockTimerService()
        let controller = try TrainingController(store: store, alarm: timer, notification: timer)
        await controller.start(plan: day); await controller.completeSet()
        let id = controller.session?.timerID
        timer.inspection = .paused(remaining: 20)
        await controller.reconcile()
        let deadline = Date().addingTimeInterval(120)
        timer.inspection = .running(end: deadline)
        await controller.reconcile()
        XCTAssertEqual(controller.session?.phase, .resting)
        XCTAssertEqual(controller.session?.restEnd, deadline)
        XCTAssertEqual(controller.session?.timerID, id)
        XCTAssertEqual(timer.starts, 1)
    }
    func testEmptyDayDoesNotCancelExistingProbeReminder() async throws {
        let store = try store(); let timer = MockTimerService(); var prepared = false
        let controller = try TrainingController(store: store, alarm: timer, notification: timer, prepare: { prepared = true })
        let empty = try TrainingPlan(name: "空训练", position: 0)
        await controller.start(plan: empty)
        XCTAssertFalse(prepared)
        XCTAssertNil(controller.session)
        XCTAssertNotNil(controller.error)
    }
}
