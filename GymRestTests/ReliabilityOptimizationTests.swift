import XCTest
import SwiftData
@testable import GymRest

@MainActor final class ReliabilityOptimizationTests: XCTestCase {
    private func store() throws -> TrainingStore {
        try TrainingStore(container: ModelContainer(for: TrainingProgram.self, TrainingPlan.self, LibraryPreferences.self, ActiveTraining.self, TrainingRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }
    private func archive() -> PlanArchive {
        PlanArchive(version: 3, plans: [.init(id: UUID(), name: "导入训练", exercises: [ExerciseSpec(name: "上斜哑铃卧推", sets: 4, restSeconds: 150,
            alternatives: [ExerciseAlternative(name: "自定义替代")], catalogID: "incline-dumbbell-bench", prescription: SetValues(weight: 20, repetitions: 8, kind: .perHand))])])
    }
    func testImportMissingFieldReportsExactPath() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(archive())) as? [String: Any])
        var plans = try XCTUnwrap(object["plans"] as? [[String: Any]])
        var exercises = try XCTUnwrap(plans[0]["exercises"] as? [[String: Any]])
        exercises[0].removeValue(forKey: "restSeconds"); plans[0]["exercises"] = exercises; object["plans"] = plans
        XCTAssertThrowsError(try PlanArchive.decode(JSONSerialization.data(withJSONObject: object))) { error in
            XCTAssertTrue(error.localizedDescription.contains("plans[0].exercises[0].restSeconds"))
        }
    }
    func testImportInvalidValueReportsDayActionAndField() throws {
        var value = archive(); value.plans[0].exercises[0].sets = 0
        XCTAssertThrowsError(try PlanArchive.decode(JSONEncoder().encode(value))) { error in
            XCTAssertTrue(error.localizedDescription.contains("导入训练")); XCTAssertTrue(error.localizedDescription.contains("sets"))
        }
    }
    func testBOMAndSingleJSONFenceAreAcceptedButExtraTextIsRejected() throws {
        let data = try JSONEncoder().encode(archive())
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(try PlanArchive.decode(Data(("\u{feff}  ```json\n" + text + "\n```  ").utf8)).plans.count, 1)
        XCTAssertThrowsError(try PlanArchive.decode(Data(("说明：" + text).utf8)))
        XCTAssertThrowsError(try PlanArchive.decode(Data(repeating: 32, count: 10 * 1024 * 1024 + 1)))
    }
    func testMatchingUpdatesOnlyChosenReferenceAndName() throws {
        let catalog = try ExerciseCatalog.bundled(); var archive = archive()
        let original = archive.plans[0].exercises[0]
        let rows = ImportActionMatcher.rows(archive, catalog: catalog)
        XCTAssertEqual(rows[0].kind, .name); XCTAssertEqual(rows[1].kind, .unmatched)
        ImportActionMatcher.assign(rows[0].target, row: rows[0], archive: &archive, useCatalogName: true)
        let updated = archive.plans[0].exercises[0]
        XCTAssertEqual(updated.catalogID, "incline-dumbbell")
        XCTAssertEqual(updated.id, original.id); XCTAssertEqual(updated.sets, original.sets)
        XCTAssertEqual(updated.prescription, original.prescription); XCTAssertEqual(updated.restSeconds, original.restSeconds)
        XCTAssertEqual(updated.alternatives, original.alternatives)
        XCTAssertNil(catalog.matching(name: "bench"))
    }
    private func record(in store: TrainingStore, values: SetValues = SetValues(weight: 30, repetitions: 10)) throws -> TrainingRecord {
        let exercise = ExerciseSpec(name: "卧推", sets: 1, catalogID: "barbell-bench")
        var session = try TrainingSession(planID: UUID(), planName: "测试训练", exercises: [exercise], fallback: false)
        session.completed = [1]; session.performedNames = [[exercise.name]]; session.phase = .completed
        session.performances = [[SetPerformance(exerciseName: exercise.name, catalogID: exercise.catalogID, values: values,
            profileKey: exercise.profileKey(for: values), completedAt: Date())]]
        let value = try TrainingRecord(session: session, end: Date()); value.workoutID = "health-reference"; value.workoutSource = "测试来源"
        store.context.insert(value); try store.context.save(); return value
    }
    private func populated() throws -> TrainingStore {
        let store = try store(); let parent = TrainingProgram(name: "我的计划", position: 0)
        let day = try TrainingPlan(name: "训练日", position: 0, exercises: [ExerciseSpec(name: "卧推")])
        day.programID = parent.id; store.context.insert(parent); store.context.insert(day)
        store.preferences.defaultRest = 75; try store.context.save(); _ = try record(in: store)
        return store
    }
    func testCompleteBackupRoundTripAndRepeatedMergeKeepHistoryAndSettings() throws {
        let source = try populated()
        let encoded = try LibraryBackup.capture(source.context, preferences: source.preferences).encoded()
        let backup = try LibraryBackup.decode(encoded); let destination = try store()
        let result = try backup.merge(into: destination.context, preferences: destination.preferences, restorePreferences: true)
        XCTAssertEqual(result.days, 1); XCTAssertEqual(result.records, 1)
        XCTAssertEqual(destination.preferences.defaultRest, 75)
        let restored = try XCTUnwrap(destination.context.fetch(FetchDescriptor<TrainingRecord>()).first)
        XCTAssertEqual(restored.workoutID, "health-reference")
        XCTAssertEqual(try restored.performances()?.first?.first?.values?.weight, 30)
        let again = try backup.merge(into: destination.context, preferences: destination.preferences, restorePreferences: false)
        XCTAssertEqual(again.skipped, 3); XCTAssertEqual(again.records, 0)
        XCTAssertEqual(try destination.context.fetch(FetchDescriptor<TrainingRecord>()).count, 1)
    }
    func testFailedBackupMergeRestoresSettingsAndDoesNotInsertPartialRows() throws {
        let source = try populated(); let backup = try LibraryBackup.capture(source.context, preferences: source.preferences)
        let destination = try store(); let rest = destination.preferences.defaultRest
        XCTAssertThrowsError(try backup.merge(into: destination.context, preferences: destination.preferences, restorePreferences: true,
                                             beforeCommit: { throw TimerFailure.denied }))
        XCTAssertEqual(destination.preferences.defaultRest, rest)
        XCTAssertTrue(try destination.context.fetch(FetchDescriptor<TrainingRecord>()).isEmpty)
        XCTAssertTrue(try destination.context.fetch(FetchDescriptor<TrainingPlan>()).isEmpty)
        XCTAssertFalse(destination.context.hasChanges)
    }
    func testBackupRestoreCannotOverwriteActiveProgressAndFileTypesAreDistinguished() throws {
        let source = try populated(); let backup = try LibraryBackup.capture(source.context, preferences: source.preferences)
        let destination = try store(); let payload = Data("unreadable active snapshot".utf8)
        destination.context.insert(ActiveTraining(payload: payload)); try destination.context.save()
        XCTAssertThrowsError(try backup.merge(into: destination.context, preferences: destination.preferences, restorePreferences: false))
        XCTAssertEqual(try destination.context.fetch(FetchDescriptor<ActiveTraining>()).first?.payload, payload)
        XCTAssertThrowsError(try PlanArchive.decode(backup.encoded()))
        XCTAssertThrowsError(try LibraryBackup.decode(JSONEncoder().encode(archive())))
    }
    func testMalformedBackupRecordIsRejectedBeforeMutation() throws {
        let source = try store()
        let bad = ExerciseSpec(name: "损坏动作", sets: -1)
        let value = TrainingRecord(id: UUID(), planName: "损坏记录", startedAt: nil, endedAt: Date(), finished: false,
            exerciseData: try JSONEncoder().encode([bad]), completedData: try JSONEncoder().encode([0]))
        source.context.insert(value); try source.context.save()
        let backup = try LibraryBackup.capture(source.context, preferences: source.preferences)
        XCTAssertThrowsError(try backup.encoded())
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        XCTAssertThrowsError(try LibraryBackup.decode(encoder.encode(backup)))
    }
    func testPreviousSetReuseKeepsMeasuredSetAndRejectsStaleInteraction() async throws {
        let store = try store(); let timer = MockTimerService()
        let controller = try TrainingController(store: store, alarm: timer, notification: timer)
        let day = try TrainingPlan(name: "训练", position: 0, exercises: [ExerciseSpec(name: "卧推", sets: 2)])
        await controller.start(plan: day)
        let first = SetValues(weight: 20, repetitions: 10)
        await controller.setValues(first, interactionID: controller.session?.interactionID); await controller.completeSet()
        let stale = controller.session?.interactionID
        await controller.setValues(SetValues(weight: 25, repetitions: 8), interactionID: stale)
        await controller.reusePreviousSet(interactionID: stale)
        XCTAssertEqual(controller.session?.currentSetValues.weight, 25)
        await controller.reusePreviousSet(interactionID: controller.session?.interactionID)
        XCTAssertEqual(controller.session?.currentSetValues, first)
        XCTAssertEqual(controller.session?.performances?.first?.first?.values, first)
        XCTAssertEqual(controller.session?.setValueOrigins?.first, "沿用本动作上一组")
        XCTAssertEqual(controller.session?.completedSets, 1)
    }
    func testHistoryComparisonSeparatesUnitsLoadKindsAndEquipmentNotes() throws {
        let store = try store()
        _ = try record(in: store, values: SetValues(weight: 20, repetitions: 10, equipmentNote: "A"))
        _ = try record(in: store, values: SetValues(weight: 40, repetitions: 10, unit: .lb, equipmentNote: "A"))
        _ = try record(in: store, values: SetValues(weight: 20, repetitions: 10, kind: .perHand, equipmentNote: "A"))
        _ = try record(in: store, values: SetValues(weight: 20, repetitions: 10, equipmentNote: "B"))
        let profiles = TrainingComparison.profiles(try store.context.fetch(FetchDescriptor<TrainingRecord>()))
        XCTAssertEqual(profiles.count, 4)
        XCTAssertTrue(profiles.allSatisfy { $0.sessions.count == 1 && $0.sessions[0].values.count == 1 })
    }
}
