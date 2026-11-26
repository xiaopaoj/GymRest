import XCTest
import SwiftData
@testable import GymRest

@MainActor final class TimedExerciseTests: XCTestCase {
    final class Clock { var date = Date(timeIntervalSince1970: 1_800_000_000); func advance(_ seconds: Double) { date = date.addingTimeInterval(seconds) } }
    struct Fixture { let store: TrainingStore; let controller: TrainingController; let timer: MockTimerService; let clock: Clock; let plan: TrainingPlan }
    private func fixture(seconds: Int? = 40, sides: Int = 2, sets: Int = 2) async throws -> Fixture {
        let container = try ModelContainer(for: TrainingProgram.self, TrainingPlan.self, LibraryPreferences.self, ActiveTraining.self, TrainingRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = try TrainingStore(container: container), timer = MockTimerService(), clock = Clock()
        let controller = try TrainingController(store: store, alarm: timer, notification: timer, now: { clock.date })
        let plan = try TrainingPlan(name: "计时测试", position: 0, exercises: [ExerciseSpec(name: "侧平板支撑", sets: sets, restSeconds: 30,
            prescription: SetValues(kind: .bodyweight, durationSeconds: seconds, sideCount: sides))])
        await controller.start(plan: plan)
        return Fixture(store: store, controller: controller, timer: timer, clock: clock, plan: plan)
    }
    func testFortySecondsEachSideCreatesOnlyOneSetAndOneRest() async throws {
        let f = try await fixture()
        await f.controller.startEffort()
        XCTAssertEqual(f.timer.lastContext?.kind, "effort")
        f.clock.advance(40); await f.controller.reconcile()
        XCTAssertEqual(f.controller.session?.completedSets, 0)
        XCTAssertEqual(f.controller.session?.effortTimer?.status, .ready)
        XCTAssertFalse(f.timer.ids.isEmpty) // Polling must not suppress the system alert.
        await f.controller.completeSet()
        XCTAssertEqual(f.controller.session?.sideProgress, 1)
        XCTAssertEqual(f.controller.session?.completedSets, 0)
        XCTAssertEqual(f.controller.session?.phase, .training)
        XCTAssertNil(f.controller.session?.effortTimer)
        await f.controller.startEffort()
        f.clock.advance(40); await f.controller.completeSet()
        XCTAssertEqual(f.controller.session?.completedSets, 1)
        XCTAssertEqual(f.controller.session?.phase, .resting)
        XCTAssertEqual(f.controller.session?.sideProgress, 0)
        XCTAssertEqual(f.timer.lastContext?.kind, "set")
        XCTAssertEqual(f.timer.starts, 3)
        let performance = try XCTUnwrap(f.controller.session?.performances?.first?.first)
        XCTAssertEqual(performance.values?.durationSeconds, 40)
        XCTAssertEqual(performance.values?.sideCount, 2)
    }
    func testTimerCannotCompleteBeforeStartOrBeforeDeadline() async throws {
        let f = try await fixture()
        await f.controller.completeSet()
        XCTAssertNotNil(f.controller.error); XCTAssertEqual(f.controller.session?.sideProgress, 0)
        await f.controller.startEffort(); f.clock.advance(39)
        await f.controller.completeSet()
        XCTAssertEqual(f.controller.session?.completedSets, 0); XCTAssertEqual(f.controller.session?.sideProgress, 0)
    }
    func testPauseDoesNotConsumeElapsedWallTimeAndResumeDoesNotConfirm() async throws {
        let f = try await fixture()
        await f.controller.startEffort(); f.clock.advance(10); await f.controller.pauseEffort()
        XCTAssertEqual(f.controller.session?.effortTimer?.remaining, 30); XCTAssertTrue(f.timer.ids.isEmpty)
        f.clock.advance(300); await f.controller.resumeEffort()
        XCTAssertEqual(f.controller.session?.effortTimer?.end, f.clock.date.addingTimeInterval(30))
        XCTAssertEqual(f.controller.session?.completedSets, 0)
    }
    func testRestartRestoresPartialSideProgressWithoutRescheduling() async throws {
        let f = try await fixture()
        await f.controller.startEffort(); f.clock.advance(40); await f.controller.completeSet()
        await f.controller.startEffort(); f.clock.advance(10)
        let restored = try TrainingController(store: f.store, alarm: f.timer, notification: f.timer, now: { f.clock.date })
        await restored.reconcile()
        XCTAssertEqual(restored.session?.sideProgress, 1); XCTAssertEqual(restored.session?.completedSets, 0)
        XCTAssertEqual(f.timer.starts, 2)
        f.clock.advance(30); await restored.completeSet()
        XCTAssertEqual(restored.session?.completedSets, 1)
    }
    func testRegistrationFailureNeverCountsAndCanRetry() async throws {
        let f = try await fixture()
        f.timer.failStart = true; await f.controller.startEffort()
        XCTAssertEqual(f.controller.session?.effortTimer?.registered, false)
        f.clock.advance(100); await f.controller.completeSet()
        XCTAssertEqual(f.controller.session?.sideProgress, 0)
        f.timer.failStart = false; await f.controller.startEffort()
        XCTAssertEqual(f.controller.session?.effortTimer?.registered, true)
        XCTAssertEqual(f.controller.session?.effortTimer?.secondsLeft(at: f.clock.date), 40)
    }
    func testCancelFailureBlocksCompletionAndKeepsReminderAndSide() async throws {
        let f = try await fixture()
        await f.controller.startEffort(); f.clock.advance(40); let before = f.controller.session
        f.timer.failCancel = true; await f.controller.completeSet()
        XCTAssertEqual(f.controller.session, before); XCTAssertNotNil(f.controller.error)
    }
    func testAlarmDismissalMarksReadyButDoesNotCompleteSide() async throws {
        let f = try await fixture()
        await f.controller.startEffort(); let id = try XCTUnwrap(f.controller.session?.effortTimer?.id)
        await f.controller.finishRestFromAlarm(timerID: id.uuidString)
        XCTAssertEqual(f.controller.session?.effortTimer?.status, .running)
        f.clock.advance(40); await f.controller.finishRestFromAlarm(timerID: id.uuidString)
        XCTAssertEqual(f.controller.session?.effortTimer?.status, .ready)
        XCTAssertEqual(f.controller.session?.sideProgress, 0); XCTAssertEqual(f.controller.session?.completedSets, 0)
    }
    func testSingleSidePlankRecordsAfterOneConfirmationAndNoAutoSet() async throws {
        let f = try await fixture(sides: 1, sets: 1)
        await f.controller.startEffort(); f.clock.advance(40); await f.controller.reconcile()
        XCTAssertEqual(f.controller.session?.completedSets, 0)
        await f.controller.completeSet()
        XCTAssertEqual(f.controller.session?.phase, .completed)
        XCTAssertNil(try f.store.load())
        let records = try f.store.context.fetch(FetchDescriptor<TrainingRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(try records[0].performances()?.first?.first?.values?.durationSeconds, 40)
    }
    func testUntimedBilateralRequiresTwoConfirmationsAndDuplicateTokenCannotReplay() async throws {
        let f = try await fixture(seconds: nil)
        let token = try XCTUnwrap(f.controller.session?.interactionID?.uuidString)
        await f.controller.handleQuickAction(.completeSet, interactionID: token)
        XCTAssertEqual(f.controller.session?.sideProgress, 1)
        f.clock.advance(1); await f.controller.handleQuickAction(.completeSet, interactionID: token)
        XCTAssertEqual(f.controller.session?.completedSets, 0)
        let next = try XCTUnwrap(f.controller.session?.interactionID?.uuidString)
        await f.controller.handleQuickAction(.completeSet, interactionID: next)
        XCTAssertEqual(f.controller.session?.completedSets, 1)
    }
    func testMidPairSettingsAndAlternativeCannotChange() async throws {
        let f = try await fixture(seconds: nil)
        await f.controller.completeSet()
        let before = f.controller.session
        await f.controller.setValues(SetValues(sideCount: 1), interactionID: before?.interactionID)
        XCTAssertEqual(f.controller.session, before)
        await f.controller.selectAlternative(nil)
        XCTAssertEqual(f.controller.session, before)
        XCTAssertTrue(f.controller.reorderableExercises.isEmpty)
    }
    func testEarlyEndDoesNotArchiveHalfAsAFullSet() async throws {
        let f = try await fixture(seconds: nil)
        await f.controller.completeSet()
        XCTAssertEqual(f.controller.session?.sideProgress, 1)
        XCTAssertEqual(f.controller.session?.completedSets, 0)
        await f.controller.end()
        let records = try f.store.context.fetch(FetchDescriptor<TrainingRecord>())
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(try record.completed(), [0])
        XCTAssertFalse(record.finished)
        // Storage is created lazily on the first whole-set completion. Both a
        // missing measurement array and an empty array represent no full sets.
        XCTAssertTrue(try (record.performances() ?? []).flatMap { $0 }.isEmpty)
        XCTAssertNil(try f.store.load())
        XCTAssertTrue(f.timer.ids.isEmpty)
    }
    func testResetCurrentSideKeepsFirstSideAndRejectsStaleAlarm() async throws {
        let f = try await fixture()
        await f.controller.startEffort(); f.clock.advance(40); await f.controller.completeSet()
        await f.controller.startEffort(); let old = try XCTUnwrap(f.controller.session?.effortTimer?.id)
        await f.controller.resetEffort(); await f.controller.startEffort()
        f.clock.advance(40); await f.controller.finishRestFromAlarm(timerID: old.uuidString)
        XCTAssertEqual(f.controller.session?.effortTimer?.status, .running)
        XCTAssertEqual(f.controller.session?.sideProgress, 1)
    }
    func testVersionFourAndOldDefaultsRoundTrip() throws {
        let old = try JSONDecoder().decode(SetValues.self, from: Data(#"{"weight":10,"repetitions":12}"#.utf8))
        XCTAssertNil(old.durationSeconds); XCTAssertEqual(old.sideCount, 1)
        XCTAssertThrowsError(try SetValues(repetitions: 10, durationSeconds: 40).validate())
        XCTAssertThrowsError(try SetValues(durationSeconds: 0).validate())
        XCTAssertThrowsError(try SetValues(sideCount: 3).validate())
        let timed = SetValues(kind: .bodyweight, durationSeconds: 40, sideCount: 2)
        let archive = PlanArchive(version: 4, plans: [.init(id: UUID(), name: "侧平板", exercises: [.init(name: "侧平板支撑", prescription: timed)])])
        let decoded = try PlanArchive.decode(JSONEncoder().encode(archive))
        XCTAssertEqual(decoded.plans[0].exercises[0].prescription, timed)
        let catalog = try ExerciseCatalog.bundled()
        XCTAssertEqual(catalog.item("guide-side-plank")?.prescription, timed)
        XCTAssertEqual(catalog.item("guide-plank")?.prescription.durationSeconds, 40)
    }
    func testWatchPromptOnlyForNewSessionsAndEnabledPreference() throws {
        XCTAssertTrue(WatchStartReminder.shouldPrompt(enabled: true, session: nil))
        XCTAssertFalse(WatchStartReminder.shouldPrompt(enabled: nil, session: nil))
        var session = try TrainingSession(planID: UUID(), planName: "测试", exercises: [.init(name: "平板")], fallback: false)
        for phase in [TrainingPhase.training, .resting, .paused] {
            session.phase = phase
            XCTAssertFalse(WatchStartReminder.shouldPrompt(enabled: true, session: session))
        }
        session.phase = .completed
        XCTAssertTrue(WatchStartReminder.shouldPrompt(enabled: true, session: session))
    }

    func testTimedPlanExportUsesVersionFourAndFullBackupUsesVersionTwo() async throws {
        let f = try await fixture()
        let exported = try PlanArchive.decode(PlanArchive.export(plans: [f.plan]))
        XCTAssertEqual(exported.version, 4)
        XCTAssertEqual(exported.plans[0].exercises[0].prescription?.durationSeconds, 40)
        let backup = try LibraryBackup.capture(f.store.context, preferences: f.store.preferences)
        XCTAssertEqual(backup.version, 2)
        XCTAssertEqual(try LibraryBackup.decode(backup.encoded()).version, 2)
    }

}
