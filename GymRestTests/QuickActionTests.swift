import XCTest
import SwiftData
@testable import GymRest

@MainActor final class QuickActionTests: XCTestCase {
    private final class Publication {
        var session: TrainingSession?
        var issue: String?
    }
    private struct Fixture {
        let store: TrainingStore
        let timer: MockTimerService
        let controller: TrainingController
        let publication: Publication
    }
    private func fixture(sets: Int = 3, restAfterLastSet: Bool = false) async throws -> Fixture {
        let container = try ModelContainer(for: TrainingProgram.self, TrainingPlan.self, LibraryPreferences.self, ActiveTraining.self, TrainingRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = try TrainingStore(container: container)
        let timer = MockTimerService(); let publication = Publication()
        let reference = Date()
        let controller = try TrainingController(store: store, alarm: timer, notification: timer,
            now: { reference },
            activitySync: { session, issue, _ in
                publication.session = session; publication.issue = issue; return nil
            })
        let day = try TrainingPlan(name: "锁屏训练", position: 10,
            exercises: [ExerciseSpec(name: "卧推", sets: sets, restSeconds: 47, restAfterLastSet: restAfterLastSet)])
        store.context.insert(day); try store.context.save()
        await controller.start(plan: day)
        return Fixture(store: store, timer: timer, controller: controller, publication: publication)
    }
    private func token(_ controller: TrainingController) throws -> String {
        try XCTUnwrap(controller.session?.interactionID).uuidString
    }
    func testLockScreenCompletionPersistsOneSetAndRegistersRest() async throws {
        let f = try await fixture(); let original = try token(f.controller)
        await f.controller.handleQuickAction(.completeSet, interactionID: original)
        XCTAssertEqual(f.controller.session?.completedSets, 1)
        XCTAssertEqual(f.controller.session?.phase, .resting)
        XCTAssertEqual(f.timer.starts, 1)
        XCTAssertEqual(f.timer.lastContext?.completedSet, 1)
        XCTAssertNotEqual(try token(f.controller), original)
        XCTAssertEqual(try f.store.load(), f.controller.session)
        XCTAssertEqual(f.publication.session, f.controller.session)
        await f.controller.handleQuickAction(.completeSet, interactionID: original)
        XCTAssertEqual(f.controller.session?.completedSets, 1)
        XCTAssertEqual(f.timer.starts, 1)
    }
    func testReplayAfterRestEndsCannotCompleteNextSet() async throws {
        let f = try await fixture(); let old = try token(f.controller)
        await f.controller.handleQuickAction(.completeSet, interactionID: old)
        await f.controller.handleQuickAction(.finishRest, interactionID: try token(f.controller))
        XCTAssertEqual(f.controller.session?.phase, .training)
        await f.controller.handleQuickAction(.completeSet, interactionID: old)
        XCTAssertEqual(f.controller.session?.completedSets, 1)
        XCTAssertTrue(f.timer.ids.isEmpty)
    }
    func testPauseResumeAndFinishUseExistingReminderLifecycle() async throws {
        let f = try await fixture()
        await f.controller.handleQuickAction(.completeSet, interactionID: try token(f.controller))
        let oldTimer = f.controller.session?.timerID
        await f.controller.handleQuickAction(.pauseRest, interactionID: try token(f.controller))
        XCTAssertEqual(f.controller.session?.phase, .paused)
        XCTAssertTrue(f.timer.ids.isEmpty)
        await f.controller.handleQuickAction(.addRest, interactionID: try token(f.controller))
        XCTAssertGreaterThan(f.controller.session?.remaining ?? 0, 47)
        await f.controller.handleQuickAction(.resumeRest, interactionID: try token(f.controller))
        XCTAssertEqual(f.controller.session?.phase, .resting)
        XCTAssertNotEqual(f.controller.session?.timerID, oldTimer)
        XCTAssertEqual(f.timer.ids.count, 1)
        await f.controller.handleQuickAction(.finishRest, interactionID: try token(f.controller))
        XCTAssertEqual(f.controller.session?.phase, .training)
        XCTAssertEqual(f.controller.session?.completedSets, 1)
        XCTAssertTrue(f.timer.ids.isEmpty)
    }
    func testUnauthorizedBackgroundCompletionDoesNotChangeProgress() async throws {
        let f = try await fixture(); f.timer.canScheduleInBackground = false
        let old = try token(f.controller)
        await f.controller.handleQuickAction(.completeSet, interactionID: old)
        XCTAssertEqual(f.controller.session?.completedSets, 0)
        XCTAssertEqual(try token(f.controller), old)
        XCTAssertEqual(f.timer.starts, 0)
        XCTAssertNotNil(f.publication.issue)
        f.timer.canScheduleInBackground = true
        await f.controller.handleQuickAction(.completeSet, interactionID: old)
        XCTAssertEqual(f.controller.session?.completedSets, 1)
        XCTAssertNil(f.publication.issue)
    }
    func testRegistrationFailureRetainsOneCompletionAndCanResume() async throws {
        let f = try await fixture(); f.timer.failStart = true
        let old = try token(f.controller)
        await f.controller.handleQuickAction(.completeSet, interactionID: old)
        XCTAssertEqual(f.controller.session?.completedSets, 1)
        XCTAssertFalse(f.controller.session?.reminderRegistered ?? true)
        XCTAssertNotNil(f.publication.issue)
        await f.controller.handleQuickAction(.completeSet, interactionID: old)
        XCTAssertEqual(f.controller.session?.completedSets, 1)
        f.timer.failStart = false
        await f.controller.handleQuickAction(.retryRest, interactionID: try token(f.controller))
        XCTAssertTrue(f.controller.session?.reminderRegistered ?? false)
        XCTAssertEqual(f.controller.session?.completedSets, 1)
    }
    func testColdControllerUsesPersistedTokenAndArchivesFinalSetOnce() async throws {
        let f = try await fixture(sets: 1)
        let old = try token(f.controller)
        let restored = try TrainingController(store: f.store, alarm: f.timer, notification: f.timer)
        XCTAssertEqual(try token(restored), old)
        await restored.handleQuickAction(.completeSet, interactionID: old)
        XCTAssertEqual(restored.session?.phase, .completed)
        XCTAssertNil(try f.store.load())
        await restored.handleQuickAction(.completeSet, interactionID: old)
        XCTAssertEqual(try f.store.context.fetch(FetchDescriptor<TrainingRecord>()).count, 1)
        XCTAssertEqual(f.timer.starts, 0)
    }
    func testOldSavedSessionGainsDurableInteractionTokenWithoutChangingProgress() async throws {
        let f = try await fixture()
        let saved = try XCTUnwrap(f.controller.session)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as? [String: Any])
        json.removeValue(forKey: "interactionID")
        let active = try XCTUnwrap(f.store.context.fetch(FetchDescriptor<ActiveTraining>()).first)
        active.payload = try JSONSerialization.data(withJSONObject: json)
        try f.store.context.save()
        let restored = try TrainingController(store: f.store, alarm: f.timer, notification: f.timer)
        XCTAssertNotNil(restored.session?.interactionID)
        XCTAssertEqual(restored.session?.completed, saved.completed)
        XCTAssertEqual(restored.session?.sessionID, saved.sessionID)
        XCTAssertEqual(restored.session?.exercises, saved.exercises)
        XCTAssertEqual(try f.store.load(), restored.session)
    }
    func testFinalSetWithRestDoesNotFinishUntilRestIsAcknowledged() async throws {
        let f = try await fixture(sets: 1, restAfterLastSet: true)
        await f.controller.handleQuickAction(.completeSet, interactionID: try token(f.controller))
        XCTAssertEqual(f.controller.session?.phase, .resting)
        await f.controller.handleQuickAction(.finishRest, interactionID: try token(f.controller))
        XCTAssertEqual(f.controller.session?.phase, .completed)
        XCTAssertTrue(f.timer.ids.isEmpty)
        XCTAssertEqual(try f.store.context.fetch(FetchDescriptor<TrainingRecord>()).count, 1)
    }
    func testCanceledReminderFailureDoesNotAdvanceToNextSet() async throws {
        let f = try await fixture()
        await f.controller.handleQuickAction(.completeSet, interactionID: try token(f.controller))
        f.timer.failCancel = true
        await f.controller.handleQuickAction(.finishRest, interactionID: try token(f.controller))
        XCTAssertEqual(f.controller.session?.phase, .resting)
        XCTAssertEqual(f.controller.session?.completedSets, 1)
        XCTAssertEqual(f.timer.ids.count, 1)
        XCTAssertNotNil(f.publication.issue)
    }
    func testActionWaitingForInspectionCannotAffectNewerAppState() async throws {
        let f = try await fixture(); let old = try token(f.controller)
        var continuation: CheckedContinuation<Void, Never>?
        f.timer.onAuthorization = { await withCheckedContinuation { continuation = $0 } }
        let action = Task { await f.controller.handleQuickAction(.completeSet, interactionID: old) }
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        guard let resume = continuation else { action.cancel(); XCTFail("Inspection did not begin"); return }
        await f.controller.end()
        resume.resume(); await action.value
        XCTAssertNil(f.controller.session)
        XCTAssertEqual(f.timer.starts, 0)
    }
    func testStoppingAlarmPreparesNextSetWithoutCompletingItAgain() async throws {
        let f = try await fixture()
        await f.controller.completeSet()
        let id = try XCTUnwrap(f.controller.session?.timerID).uuidString
        // AlarmKit may already have removed the alert before it calls the stop intent.
        f.timer.ids.removeAll()
        await f.controller.finishRestFromAlarm(timerID: id)
        XCTAssertEqual(f.controller.session?.phase, .training)
        XCTAssertEqual(f.controller.session?.completedSets, 1)
        XCTAssertNil(f.controller.session?.timerID)
        XCTAssertEqual(f.publication.session, f.controller.session)
        XCTAssertEqual(try f.store.load(), f.controller.session)
        await f.controller.finishRestFromAlarm(timerID: id)
        XCTAssertEqual(f.controller.session?.completedSets, 1)
    }
    func testDelayedAlarmStopCannotEndReplacementRest() async throws {
        let f = try await fixture()
        await f.controller.completeSet()
        let oldID = try XCTUnwrap(f.controller.session?.timerID).uuidString
        await f.controller.restartRest()
        let replacement = f.controller.session
        await f.controller.finishRestFromAlarm(timerID: oldID)
        XCTAssertEqual(f.controller.session, replacement)
        XCTAssertEqual(f.timer.ids.count, 1)
    }
    func testAlarmStopCancellationFailureKeepsRestAndDisplaysError() async throws {
        let f = try await fixture()
        await f.controller.completeSet()
        let id = try XCTUnwrap(f.controller.session?.timerID).uuidString
        f.timer.failCancel = true
        await f.controller.finishRestFromAlarm(timerID: id)
        XCTAssertEqual(f.controller.session?.phase, .resting)
        XCTAssertEqual(f.controller.session?.completedSets, 1)
        XCTAssertNotNil(f.publication.issue)
        XCTAssertEqual(f.timer.ids.count, 1)
    }
    func testStoppingFinalRestArchivesExactlyOnce() async throws {
        let f = try await fixture(sets: 1, restAfterLastSet: true)
        await f.controller.completeSet()
        let id = try XCTUnwrap(f.controller.session?.timerID).uuidString
        await f.controller.finishRestFromAlarm(timerID: id)
        await f.controller.finishRestFromAlarm(timerID: id)
        XCTAssertEqual(f.controller.session?.phase, .completed)
        XCTAssertEqual(try f.store.context.fetch(FetchDescriptor<TrainingRecord>()).count, 1)
        XCTAssertNil(try f.store.load())
    }
}
