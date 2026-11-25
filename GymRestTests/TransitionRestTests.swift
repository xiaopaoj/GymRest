import XCTest
import SwiftData
@testable import GymRest

@MainActor final class TransitionRestTests: XCTestCase {
    private final class Clock { var date = Date() }
    private struct Fixture {
        let store: TrainingStore
        let day: TrainingPlan
        let timer: MockTimerService
        let controller: TrainingController
        let clock: Clock
    }
    private func fixture(_ exercises: [ExerciseSpec]) async throws -> Fixture {
        let container = try ModelContainer(for: TrainingProgram.self, TrainingPlan.self, LibraryPreferences.self, ActiveTraining.self, TrainingRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = try TrainingStore(container: container); let timer = MockTimerService(); let clock = Clock()
        let controller = try TrainingController(store: store, alarm: timer, notification: timer, now: { clock.date })
        let day = try TrainingPlan(name: "动作间休息", position: 10, exercises: exercises)
        store.context.insert(day); try store.context.save(); await controller.start(plan: day)
        return Fixture(store: store, day: day, timer: timer, controller: controller, clock: clock)
    }
    private var next: ExerciseSpec { ExerciseSpec(name: "划船", sets: 1, restSeconds: 60) }
    func testSetRestAndTransitionRestAreIndependentAndAdvanceOnlyAfterRest() async throws {
        let f = try await fixture([ExerciseSpec(name: "卧推", sets: 2, restSeconds: 60, restOverrides: [1: 45, 2: 300], transitionRestSeconds: 180), next])
        await f.controller.completeSet()
        XCTAssertEqual(f.controller.session?.originalRest, 45)
        XCTAssertFalse(f.controller.session?.isTransitionRest ?? true)
        await f.controller.skipRest(); f.clock.date.addTimeInterval(1)
        await f.controller.completeSet()
        XCTAssertEqual(f.controller.session?.originalRest, 180)
        XCTAssertEqual(f.controller.session?.index, 0)
        XCTAssertEqual(f.controller.session?.phase, .resting)
        XCTAssertTrue(f.controller.session?.isTransitionRest ?? false)
        XCTAssertEqual(f.timer.lastContext?.kind, "transition")
        XCTAssertEqual(f.timer.lastContext?.nextStep, "下一动作：划船")
        XCTAssertEqual(try f.store.load(), f.controller.session)
        await f.controller.finishRestFromAlarm(timerID: try XCTUnwrap(f.controller.session?.timerID).uuidString)
        XCTAssertEqual(f.controller.session?.index, 1)
        XCTAssertEqual(f.controller.session?.phase, .training)
        XCTAssertEqual(f.controller.session?.completedSets, 2)
        XCTAssertTrue(f.timer.ids.isEmpty)
    }
    func testExplicitZeroSkipsTransitionEvenWithLegacyLastSetSwitchEnabled() async throws {
        let f = try await fixture([ExerciseSpec(name: "卧推", sets: 1, restAfterLastSet: true, transitionRestSeconds: 0), next])
        await f.controller.completeSet()
        XCTAssertEqual(f.controller.session?.index, 1)
        XCTAssertEqual(f.controller.session?.phase, .training)
        XCTAssertEqual(f.timer.starts, 0)
    }
    func testFinalExerciseDoesNotCreateTransitionRest() async throws {
        let f = try await fixture([ExerciseSpec(name: "卧推", sets: 1, transitionRestSeconds: 180)])
        await f.controller.completeSet()
        XCTAssertEqual(f.controller.session?.phase, .completed)
        XCTAssertEqual(f.timer.starts, 0)
        XCTAssertEqual(try f.store.context.fetch(FetchDescriptor<TrainingRecord>()).count, 1)
    }
    func testFinalExerciseStillHonorsExplicitEndOfTrainingRest() async throws {
        let f = try await fixture([ExerciseSpec(name: "卧推", sets: 1, restAfterLastSet: true, restOverrides: [1: 75], transitionRestSeconds: 180)])
        await f.controller.completeSet()
        XCTAssertEqual(f.controller.session?.phase, .resting)
        XCTAssertEqual(f.controller.session?.originalRest, 75)
        XCTAssertFalse(f.controller.session?.isTransitionRest ?? true)
    }
    func testLegacyJSONKeepsBothPreviousFinalSetBehaviors() throws {
        for enabled in [false, true] {
            let source = ExerciseSpec(name: "卧推", sets: 1, restAfterLastSet: enabled, restOverrides: [1: 120])
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any])
            json.removeValue(forKey: "transitionRestSeconds")
            let restored = try JSONDecoder().decode(ExerciseSpec.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertNil(restored.transitionRestSeconds)
            let session = try TrainingSession(planID: UUID(), planName: "旧计划", exercises: [restored, next], fallback: false)
            XCTAssertEqual(session.restDuration(afterSet: 1), enabled ? 120 : nil)
        }
    }
    func testAlternativeKeepsSharedTransitionAndColdRestoreKeepsPausedProgress() async throws {
        let option = ExerciseAlternative(name: "哑铃卧推", restSeconds: 42)
        let f = try await fixture([ExerciseSpec(name: "卧推", sets: 1, alternatives: [option], transitionRestSeconds: 180), next])
        await f.controller.selectAlternative(option.id)
        await f.controller.completeSet(); await f.controller.pause()
        let restored = try TrainingController(store: f.store, alarm: f.timer, notification: f.timer, now: { f.clock.date })
        XCTAssertTrue(restored.session?.isTransitionRest ?? false)
        XCTAssertEqual(restored.session?.remaining, 180)
        XCTAssertEqual(restored.session?.index, 0)
        XCTAssertEqual(restored.session?.current.transitionRestSeconds, 180)
        await restored.resume()
        await restored.finishRestFromAlarm(timerID: try XCTUnwrap(restored.session?.timerID).uuidString)
        XCTAssertEqual(restored.session?.index, 1)
        XCTAssertEqual(restored.session?.completedSets, 1)
        XCTAssertEqual(restored.session?.performedNames?.first, ["哑铃卧推"])
    }
    func testLockScreenPermissionPreflightIncludesTransitionRest() async throws {
        let f = try await fixture([ExerciseSpec(name: "卧推", sets: 1, transitionRestSeconds: 180), next])
        f.timer.canScheduleInBackground = false
        await f.controller.handleQuickAction(.completeSet, interactionID: try XCTUnwrap(f.controller.session?.interactionID).uuidString)
        XCTAssertEqual(f.controller.session?.completedSets, 0)
        XCTAssertEqual(f.controller.session?.index, 0)
        XCTAssertEqual(f.timer.starts, 0)
        XCTAssertNotNil(f.controller.error)
    }
    func testArchiveRoundTripAndInvalidTransitionCannotPartiallyImport() async throws {
        let source = ExerciseSpec(name: "卧推", sets: 1, transitionRestSeconds: 180)
        let f = try await fixture([source, next])
        let archive = try PlanArchive.decode(PlanArchive.export(plans: [f.day]))
        XCTAssertEqual(archive.plans.first?.exercises.first?.transitionRestSeconds, 180)
        try archive.append(to: f.store.context)
        let copy = try XCTUnwrap(f.store.context.fetch(FetchDescriptor<TrainingPlan>()).first { $0.id != f.day.id && $0.name == f.day.name })
        XCTAssertEqual(try copy.exercises().first?.transitionRestSeconds, 180)
        let count = try f.store.context.fetch(FetchDescriptor<TrainingPlan>()).count
        for seconds in [-1, 86401] {
            var invalid = source; invalid.transitionRestSeconds = seconds
            XCTAssertThrowsError(try invalid.validate())
            invalid.id = UUID()
            let bad = PlanArchive(plans: [.init(id: UUID(), name: "非法", exercises: [source, invalid])])
            XCTAssertThrowsError(try PlanArchive.decode(JSONEncoder().encode(bad)))
            XCTAssertThrowsError(try bad.append(to: f.store.context))
            XCTAssertEqual(try f.store.context.fetch(FetchDescriptor<TrainingPlan>()).count, count)
        }
        var boundary = source
        for seconds in [0, 86400] { boundary.transitionRestSeconds = seconds; XCTAssertNoThrow(try boundary.validate()) }
    }
}
