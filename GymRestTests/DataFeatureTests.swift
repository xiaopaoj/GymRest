import XCTest
import SwiftData
@testable import GymRest

@MainActor final class DataFeatureTests: XCTestCase {
    private func store() throws -> TrainingStore {
        let container = try ModelContainer(for: TrainingProgram.self, TrainingPlan.self, LibraryPreferences.self, ActiveTraining.self, TrainingRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return try TrainingStore(container: container)
    }
    func testOldExerciseDecodesWithoutOverrides() throws {
        let data = Data("""
        {"id":"00000000-0000-0000-0000-000000000001","name":"卧推","sets":3,"restSeconds":60,"restAfterLastSet":false}
        """.utf8)
        let exercise = try JSONDecoder().decode(ExerciseSpec.self, from: data)
        XCTAssertTrue(exercise.restOverrides.isEmpty)
        XCTAssertEqual(exercise.rest(afterSet: 2), 60)
    }
    func testOverrideBoundsAndRoundTrip() throws {
        var exercise = ExerciseSpec(name: "卧推", sets: 3, restSeconds: 60, restOverrides: [2: 120])
        try exercise.validate()
        XCTAssertEqual(exercise.rest(afterSet: 1), 60)
        XCTAssertEqual(exercise.rest(afterSet: 2), 120)
        XCTAssertEqual(try JSONDecoder().decode(ExerciseSpec.self, from: JSONEncoder().encode(exercise)), exercise)
        exercise.restOverrides[4] = 90
        XCTAssertThrowsError(try exercise.validate())
        exercise.restOverrides = [2: 0]
        XCTAssertThrowsError(try exercise.validate())
    }
    func testArchiveRejectsInvalidVersionAndDuplicateIDs() throws {
        let entry = PlanArchive.Entry(id: UUID(), name: "计划", exercises: [ExerciseSpec(name: "卧推")])
        XCTAssertThrowsError(try PlanArchive(version: 99, plans: [entry]).validate())
        XCTAssertThrowsError(try PlanArchive(plans: [entry, entry]).validate())
        XCTAssertThrowsError(try PlanArchive.decode(Data("{}".utf8)))
    }
    func testImportValidatesEntireFileBeforeMutatingStore() throws {
        let store = try store()
        let before = try store.context.fetch(FetchDescriptor<TrainingPlan>()).count
        let archive = PlanArchive(plans: [
            .init(id: UUID(), name: "有效", exercises: []),
            .init(id: UUID(), name: "无效", exercises: [ExerciseSpec(name: "错误", restSeconds: -1)])])
        XCTAssertThrowsError(try archive.append(to: store.context))
        XCTAssertEqual(try store.context.fetch(FetchDescriptor<TrainingPlan>()).count, before)
    }
    func testImportAppendsWithNewIdentitiesAndPreservesOverrides() throws {
        let store = try store()
        let exercise = ExerciseSpec(name: "卧推", sets: 3, restOverrides: [2: 120])
        let entry = PlanArchive.Entry(id: UUID(), name: "导入计划", exercises: [exercise])
        let data = try JSONEncoder().encode(PlanArchive(plans: [entry]))
        try PlanArchive.decode(data).append(to: store.context)
        let plans = try store.context.fetch(FetchDescriptor<TrainingPlan>())
        XCTAssertEqual(plans.count, 6)
        let imported = try XCTUnwrap(plans.first(where: { $0.name == "导入计划" }))
        XCTAssertNotEqual(imported.id, entry.id)
        let value = try XCTUnwrap(imported.exercises().first)
        XCTAssertNotEqual(value.id, exercise.id)
        XCTAssertEqual(value.restOverrides[2], 120)
        XCTAssertNoThrow(try PlanArchive.decode(PlanArchive.export(plans: plans)))
    }
    func testCompletionArchivesOnceAndClearsOnlyActiveState() throws {
        let store = try store()
        var session = try TrainingSession(planID: UUID(), planName: "训练", exercises: [ExerciseSpec(name: "卧推", sets: 1)], fallback: false)
        try store.save(session)
        session.completed = [1]; session.phase = .completed
        try store.save(session)
        try store.finish(session, at: Date())
        XCTAssertNil(try store.load())
        let records = try store.context.fetch(FetchDescriptor<TrainingRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertTrue(records[0].finished)
        XCTAssertEqual(try records[0].completed(), [1])
    }
    func testEarlyEndArchivesPartialCompletion() throws {
        let store = try store()
        var session = try TrainingSession(planID: UUID(), planName: "训练", exercises: [ExerciseSpec(name: "卧推", sets: 4)], fallback: false)
        session.completed = [2]
        try store.finish(session, at: Date())
        let record = try XCTUnwrap(store.context.fetch(FetchDescriptor<TrainingRecord>()).first)
        XCTAssertFalse(record.finished)
        XCTAssertEqual(try record.completed(), [2])
    }
    func testWorkoutMatchingScoresTimeOverlapWithoutAssumingSource() {
        let start = Date(timeIntervalSince1970: 1000)
        let candidate = WorkoutCandidate(id: UUID(), start: start, end: start.addingTimeInterval(600), title: "力量", source: "其他App", device: nil)
        XCTAssertEqual(candidate.overlapScore(start: start, end: start.addingTimeInterval(600)), 1)
        XCTAssertEqual(candidate.overlapScore(start: start.addingTimeInterval(600), end: start.addingTimeInterval(1200)), 0)
        XCTAssertEqual(candidate.overlapScore(start: start, end: start.addingTimeInterval(300)), 0.5)
    }
    func testDeletingCompletedRecordIsNotUndoneByDismissingCompletion() async throws {
        let store = try store()
        let timer = MockTimerService()
        let controller = try TrainingController(store: store, alarm: timer, notification: timer)
        let plan = try TrainingPlan(name: "训练", position: 0, exercises: [ExerciseSpec(name: "卧推", sets: 1)])
        await controller.start(plan: plan)
        await controller.completeSet()
        for record in try store.context.fetch(FetchDescriptor<TrainingRecord>()) { store.context.delete(record) }
        try store.context.save()
        await controller.end()
        XCTAssertTrue(try store.context.fetch(FetchDescriptor<TrainingRecord>()).isEmpty)
    }
    func testAlternativeValidationRejectsBadRestGroupAndDuplicateID() throws {
        let option = ExerciseAlternative(name: "哑铃卧推", restSeconds: 90, restOverrides: [5: 100])
        XCTAssertThrowsError(try option.validate(sets: 4))
        let id = UUID()
        XCTAssertThrowsError(try ExerciseSpec(id: id, name: "卧推", alternatives: [ExerciseAlternative(id: id, name: "替代")]).validate())
    }
    func testAlternativeSwitchPreservesActualSetNamesAndUsesIndependentRest() async throws {
        let store = try store(); let timer = MockTimerService()
        var date = Date()
        let controller = try TrainingController(store: store, alarm: timer, notification: timer, now: { date })
        let alternative = ExerciseAlternative(name: "哑铃卧推", restSeconds: 90)
        let plan = try TrainingPlan(name: "胸部", position: 0, exercises: [ExerciseSpec(name: "杠铃卧推", sets: 3, restSeconds: 120, alternatives: [alternative])])
        await controller.start(plan: plan)
        await controller.completeSet()
        await controller.selectAlternative(alternative.id) // Resting cannot change the action.
        XCTAssertEqual(controller.session?.current.name, "杠铃卧推")
        await controller.skipRest()
        await controller.selectAlternative(alternative.id)
        XCTAssertEqual(controller.session?.completedSets, 1)
        date = date.addingTimeInterval(1)
        await controller.completeSet()
        XCTAssertEqual(controller.session?.originalRest, 90)
        XCTAssertEqual(controller.session?.performedNames?.first, ["杠铃卧推", "哑铃卧推"])
        let restored = try XCTUnwrap(store.load())
        XCTAssertEqual(restored.current.name, "哑铃卧推")
        XCTAssertEqual(restored.originalExercises?.first?.name, "杠铃卧推")
        await controller.skipRest()
        await controller.selectAlternative(nil)
        XCTAssertEqual(controller.session?.current.restSeconds, 120)
        XCTAssertEqual(try plan.exercises().first?.name, "杠铃卧推")
        await controller.end()
        let record = try XCTUnwrap(store.context.fetch(FetchDescriptor<TrainingRecord>()).first)
        let data = try XCTUnwrap(record.performedNamesData)
        XCTAssertEqual(try JSONDecoder().decode([[String]].self, from: data).first, ["杠铃卧推", "哑铃卧推"])
    }
    func testAlternativeImportExportPreservesOptionsAndRegeneratesIDs() throws {
        let store = try store()
        let option = ExerciseAlternative(name: "哑铃卧推", restSeconds: 90, restOverrides: [2: 120])
        let archive = PlanArchive(plans: [.init(id: UUID(), name: "替代测试", exercises: [ExerciseSpec(name: "卧推", alternatives: [option])])])
        try PlanArchive.decode(JSONEncoder().encode(archive)).append(to: store.context)
        let imported = try XCTUnwrap(store.context.fetch(FetchDescriptor<TrainingPlan>()).first(where: { $0.name == "替代测试" }))
        let importedOption = try XCTUnwrap(imported.exercises().first?.alternatives.first)
        XCTAssertNotEqual(importedOption.id, option.id)
        XCTAssertEqual(importedOption.restOverrides, [2: 120])
        XCTAssertEqual(try PlanArchive.decode(PlanArchive.export(plans: [imported])).plans.first?.exercises.first?.alternatives.first?.name, "哑铃卧推")
    }
    func testTimerReceivesOverrideAndTrainingContext() async throws {
        let store = try store()
        let timer = MockTimerService()
        let controller = try TrainingController(store: store, alarm: timer, notification: timer)
        let plan = try TrainingPlan(name: "胸部", position: 0, exercises: [ExerciseSpec(name: "卧推", sets: 3, restSeconds: 60, restOverrides: [1: 120])])
        await controller.start(plan: plan)
        await controller.completeSet()
        XCTAssertEqual(controller.session?.originalRest, 120)
        XCTAssertEqual(timer.lastContext?.exerciseName, "卧推")
        XCTAssertEqual(timer.lastContext?.completedSet, 1)
        await controller.adjust(by: 15)
        XCTAssertEqual(timer.lastContext?.planName, "胸部")
        XCTAssertEqual(controller.session?.current.restOverrides[1], 120)
    }
}
