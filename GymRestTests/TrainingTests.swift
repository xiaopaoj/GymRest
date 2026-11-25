import XCTest
import SwiftData
@testable import GymRest

@MainActor
final class TrainingTests: XCTestCase {
    final class Clock {
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        func advance(_ seconds: Double = 1) { date = date.addingTimeInterval(seconds) }
    }
    struct Fixture {
        let store: TrainingStore
        let controller: TrainingController
        let timer: MockTimerService
        let clock: Clock
        let plan: TrainingPlan
    }
    private func fixture(_ exercises: [ExerciseSpec]) throws -> Fixture {
        let container = try ModelContainer(for: TrainingPlan.self, LibraryPreferences.self, ActiveTraining.self, TrainingRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = try TrainingStore(container: container)
        let timer = MockTimerService()
        let clock = Clock()
        let controller = try TrainingController(store: store, alarm: timer, notification: timer, now: { clock.date })
        let plan = try TrainingPlan(name: "测试", position: 10, exercises: exercises)
        return Fixture(store: store, controller: controller, timer: timer, clock: clock, plan: plan)
    }
    func testSeedsOnlyOnceAndAllowsDeletingAllPlans() throws {
        let f = try fixture([])
        let context = f.store.context
        XCTAssertEqual(try context.fetch(FetchDescriptor<TrainingPlan>()).count, 5)
        for plan in try context.fetch(FetchDescriptor<TrainingPlan>()) { context.delete(plan) }
        try context.save()
        _ = try TrainingStore(container: context.container)
        XCTAssertTrue(try context.fetch(FetchDescriptor<TrainingPlan>()).isEmpty)
    }
    func testEmptyPlanCannotStart() async throws {
        let f = try fixture([])
        await f.controller.start(plan: f.plan)
        XCTAssertNil(f.controller.session)
        XCTAssertNotNil(f.controller.error)
    }
    func testIndependentRestAndNoAutomaticSets() async throws {
        let f = try fixture([ExerciseSpec(name: "卧推", sets: 2, restSeconds: 45), ExerciseSpec(name: "飞鸟", sets: 2, restSeconds: 120)])
        await f.controller.start(plan: f.plan)
        await f.controller.completeSet()
        XCTAssertEqual(f.controller.session?.originalRest, 45)
        f.clock.advance(46)
        await f.controller.reconcile()
        XCTAssertEqual(f.controller.session?.phase, .training)
        XCTAssertEqual(f.controller.session?.completedSets, 1) // Expiry does not complete a set.
        await f.controller.completeSet()
        XCTAssertEqual(f.controller.session?.index, 1) // Last set skips rest by default.
        XCTAssertEqual(f.controller.session?.phase, .training)
        f.clock.advance()
        await f.controller.completeSet()
        XCTAssertEqual(f.controller.session?.originalRest, 120)
    }
    func testDuplicateTapAndCompletionClearsPersistentState() async throws {
        let f = try fixture([ExerciseSpec(name: "卧推", sets: 2, restSeconds: 30)])
        await f.controller.start(plan: f.plan)
        await f.controller.completeSet()
        await f.controller.completeSet()
        XCTAssertEqual(f.controller.session?.completedSets, 1)
        XCTAssertEqual(f.timer.starts, 1)
        await f.controller.skipRest()
        f.clock.advance()
        await f.controller.completeSet()
        XCTAssertEqual(f.controller.session?.phase, .completed)
        XCTAssertNil(try f.store.load())
        XCTAssertTrue(f.timer.ids.isEmpty)
    }
    func testPauseAdjustResumeAndPresetIsUnchanged() async throws {
        let f = try fixture([ExerciseSpec(name: "卧推", sets: 3, restSeconds: 60)])
        await f.controller.start(plan: f.plan)
        await f.controller.completeSet()
        f.clock.advance(10)
        await f.controller.pause()
        XCTAssertTrue(f.timer.ids.isEmpty)
        XCTAssertEqual(f.controller.session?.remaining, 50)
        f.clock.advance(300)
        await f.controller.adjust(by: 15)
        await f.controller.resume()
        XCTAssertEqual(f.controller.session?.remaining, 65)
        XCTAssertEqual(f.controller.session?.current.restSeconds, 60)
        XCTAssertEqual(f.timer.ids.count, 1)
        await f.controller.adjust(by: -1000)
        XCTAssertEqual(f.controller.session?.phase, .training)
        XCTAssertEqual(f.controller.session?.completedSets, 1)
        XCTAssertTrue(f.timer.ids.isEmpty)
    }
    func testLastSetOptInRest() async throws {
        let f = try fixture([ExerciseSpec(name: "卧推", sets: 1, restSeconds: 30, restAfterLastSet: true)])
        await f.controller.start(plan: f.plan)
        await f.controller.completeSet()
        XCTAssertEqual(f.controller.session?.phase, .resting)
        await f.controller.skipRest()
        XCTAssertEqual(f.controller.session?.phase, .completed)
        XCTAssertNil(try f.store.load())
    }
    func testFailedRegistrationRetainsCompletedSetForRetry() async throws {
        let f = try fixture([ExerciseSpec(name: "卧推", sets: 2, restSeconds: 30)])
        await f.controller.start(plan: f.plan)
        f.timer.failStart = true
        await f.controller.completeSet()
        XCTAssertEqual(f.controller.session?.completedSets, 1)
        XCTAssertEqual(f.controller.session?.reminderRegistered, false)
        XCTAssertNotNil(f.controller.error)
        f.timer.failStart = false
        await f.controller.restartRest()
        XCTAssertEqual(f.controller.session?.reminderRegistered, true)
        XCTAssertEqual(f.controller.session?.completedSets, 1)
    }
    func testCancellationFailureBlocksNavigationAndNewReminder() async throws {
        let f = try fixture([ExerciseSpec(name: "卧推", sets: 2), ExerciseSpec(name: "飞鸟")])
        await f.controller.start(plan: f.plan)
        await f.controller.completeSet()
        let before = f.controller.session
        f.timer.failCancel = true
        await f.controller.navigate(previous: false)
        XCTAssertEqual(f.controller.session, before)
        await f.controller.adjust(by: 15)
        XCTAssertEqual(f.timer.starts, 1)
        XCTAssertNotNil(f.controller.error)
    }
    func testRestoreUsesSystemDeadlineAndNeverRegistersAgain() async throws {
        let f = try fixture([ExerciseSpec(name: "卧推", sets: 2)])
        await f.controller.start(plan: f.plan)
        await f.controller.completeSet()
        let restored = try TrainingController(store: f.store, alarm: f.timer, notification: f.timer, now: { f.clock.date })
        let calibrated = f.clock.date.addingTimeInterval(200)
        f.timer.inspection = .running(end: calibrated)
        await restored.reconcile()
        XCTAssertEqual(restored.session?.restEnd, calibrated)
        XCTAssertEqual(f.timer.starts, 1)
        XCTAssertEqual(restored.session?.completedSets, 1)
    }
    func testMissingEarlyReminderDoesNotPretendRestIsComplete() async throws {
        let f = try fixture([ExerciseSpec(name: "卧推", sets: 2)])
        await f.controller.start(plan: f.plan)
        await f.controller.completeSet()
        f.timer.ids.removeAll()
        await f.controller.reconcile()
        XCTAssertEqual(f.controller.session?.phase, .resting)
        XCTAssertNotNil(f.controller.error)
    }
    func testPlanEditsDoNotChangeRunningSnapshot() async throws {
        let f = try fixture([ExerciseSpec(name: "卧推", sets: 2, restSeconds: 30)])
        await f.controller.start(plan: f.plan)
        try f.plan.setExercises([ExerciseSpec(name: "已修改", sets: 8, restSeconds: 300)])
        await f.controller.completeSet()
        XCTAssertEqual(f.controller.session?.current.name, "卧推")
        XCTAssertEqual(f.controller.session?.originalRest, 30)
    }
}
