import XCTest
import SwiftData
import UserNotifications
@testable import GymRest

@MainActor final class OptimizationTests: XCTestCase {
    private func store() throws -> TrainingStore {
        try TrainingStore(container: ModelContainer(for: TrainingProgram.self, TrainingPlan.self, LibraryPreferences.self, ActiveTraining.self, TrainingRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }
    private func session() throws -> TrainingSession {
        try TrainingSession(planID: UUID(), planName: "训练", exercises: [ExerciseSpec(name: "卧推", sets: 3)], fallback: false)
    }
    func testUnfinishedTrainingCannotRestoreAnAlreadyFinishedCurrentSet() throws {
        var value = try session(); value.completed = [3]; value.performedNames = nil
        XCTAssertThrowsError(try value.validate())
    }
    func testTrainingCannotRestoreWithAnOrphanSystemTimer() throws {
        var value = try session(); value.timerID = UUID()
        XCTAssertThrowsError(try value.validate())
    }
    func testRestCannotRestoreWithoutAManuallyCompletedSet() throws {
        var value = try session(); value.phase = .resting; value.timerID = UUID()
        value.restEnd = Date().addingTimeInterval(60); value.originalRest = 60
        XCTAssertThrowsError(try value.validate())
    }
    func testSwitchingCannotChangeSlotSetCountAfterRestoration() throws {
        var value = try session(); value.originalExercises?[0].sets = 5
        XCTAssertThrowsError(try value.validate())
    }
    func testInvalidActiveSavePreservesPreviousStoredSession() throws {
        let store = try store(); let valid = try session(); try store.save(valid)
        var invalid = valid; invalid.timerID = UUID()
        XCTAssertThrowsError(try store.save(invalid))
        XCTAssertEqual(try store.load(), valid)
    }
    func testOverviewDistinguishesTemplatesRealProgramsAndOrphans() throws {
        let parent = TrainingProgram(name: "五分化", position: 0)
        let emptyParent = TrainingProgram(name: "模板", position: 1)
        let active = try TrainingPlan(name: "周一", position: 0, exercises: [ExerciseSpec(name: "卧推", sets: 4)])
        active.programID = parent.id
        let blank = try TrainingPlan(name: "空白", position: 1); blank.programID = emptyParent.id
        let orphan = try TrainingPlan(name: "旧训练", position: 2); orphan.programID = UUID()
        let overview = TrainingLibraryOverview(programs: [parent, emptyParent], days: [active, blank, orphan])
        XCTAssertEqual(overview.summaries[active.id]?.setCount, 4)
        XCTAssertEqual(overview.grouped[parent.id]?.map(\.id), [active.id])
        XCTAssertEqual(overview.templateIDs, Set([emptyParent.id]))
        XCTAssertEqual(overview.unassigned.map(\.id), [orphan.id])
    }
    func testUnreadableDayIsNotSilentlyClassifiedAsEmptyTemplate() throws {
        let parent = TrainingProgram(name: "需检查", position: 0)
        let day = try TrainingPlan(name: "损坏数据", position: 0); day.programID = parent.id
        day.exerciseData = Data("invalid JSON".utf8)
        let overview = TrainingLibraryOverview(programs: [parent], days: [day])
        XCTAssertNil(overview.summaries[day.id]?.exerciseCount)
        XCTAssertFalse(overview.templateIDs.contains(parent.id))
    }
    func testSemanticallyInvalidDayIsFlaggedInsteadOfCounted() throws {
        let parent = TrainingProgram(name: "需检查", position: 0)
        let day = try TrainingPlan(name: "无效组数", position: 0, exercises: [ExerciseSpec(name: "卧推", sets: 0)])
        day.programID = parent.id
        let overview = TrainingLibraryOverview(programs: [parent], days: [day])
        XCTAssertNil(overview.summaries[day.id]?.setCount)
        XCTAssertFalse(overview.templateIDs.contains(parent.id))
    }
    func testCancelledBackgroundQueryCannotPublishPermissionState() async throws {
        let store = try store(); let timer = MockTimerService()
        var continuation: CheckedContinuation<Void, Never>?
        timer.onAuthorization = { await withCheckedContinuation { continuation = $0 } }
        let controller = try TrainingController(store: store, alarm: timer, notification: timer)
        let background = Task { await controller.reconcile() }
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        guard let resume = continuation else { background.cancel(); XCTFail("Query did not begin"); return }
        background.cancel(); resume.resume(); await background.value
        XCTAssertEqual(controller.permission, "尚未查询")
        XCTAssertFalse(controller.busy)
        XCTAssertNil(controller.error)
    }
    func testRelativeNotificationDoesNotInventAnAbsoluteDeadline() {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
        XCTAssertNil(LocalNotificationTimerService.absoluteDeadline(for: trigger))
    }
    func testRepeatedRelativeInspectionsDoNotExtendRest() async throws {
        let store = try store(); let timer = MockTimerService(); var date = Date()
        let controller = try TrainingController(store: store, alarm: timer, notification: timer, now: { date })
        let plan = try TrainingPlan(name: "周一", position: 0, exercises: [ExerciseSpec(name: "卧推", sets: 3, restSeconds: 60)])
        await controller.start(plan: plan); await controller.completeSet()
        let deadline = controller.session?.restEnd
        timer.inspection = .running(end: nil)
        date = date.addingTimeInterval(20); await controller.reconcile()
        XCTAssertEqual(controller.session?.restEnd, deadline)
        XCTAssertEqual(controller.session?.secondsLeft(at: date), 40)
        date = date.addingTimeInterval(41); await controller.reconcile()
        XCTAssertEqual(controller.session?.phase, .training)
        XCTAssertEqual(controller.session?.completedSets, 1)
        XCTAssertTrue(timer.ids.isEmpty)
    }
}
