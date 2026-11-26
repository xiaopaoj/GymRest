import XCTest
import SwiftData
@testable import GymRest

@MainActor final class CatalogPerformanceTests: XCTestCase {
    private final class Clock { var now = Date() }
    private struct Fixture {
        let store: TrainingStore
        let day: TrainingPlan
        let timer: MockTimerService
        let controller: TrainingController
        let clock: Clock
    }
    private func store() throws -> TrainingStore {
        try TrainingStore(container: ModelContainer(for: TrainingProgram.self, TrainingPlan.self, LibraryPreferences.self, ActiveTraining.self, TrainingRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }
    private func fixture(_ exercises: [ExerciseSpec]) async throws -> Fixture {
        let store = try store(); let timer = MockTimerService(); let clock = Clock()
        let day = try TrainingPlan(name: "负重测试", position: 20, exercises: exercises)
        store.context.insert(day); try store.context.save()
        let controller = try TrainingController(store: store, alarm: timer, notification: timer, now: { clock.now })
        await controller.start(plan: day)
        return Fixture(store: store, day: day, timer: timer, controller: controller, clock: clock)
    }
    func testBundledCatalogAndTemplateSlotsHaveValidatedData() throws {
        let catalog = try ExerciseCatalog.bundled()
        XCTAssertGreaterThanOrEqual(catalog.exercises.count, 300)
        for template in TrainingTemplate.all {
            for day in template.days { for id in day.slots { XCTAssertNotNil(catalog.item(id)) } }
            let built = try template.build(catalog: catalog, equipment: Set(ExerciseCatalog.equipmentNames.keys), selections: [:], priority: nil)
            XCTAssertEqual(built.count, template.days.count)
            for day in built { for exercise in day { try exercise.validate(); XCTAssertNotNil(exercise.catalogID) } }
        }
    }
    func testAlternativesPreserveMovementAndDoNotSubstitutePressForSideRaise() throws {
        let catalog = try ExerciseCatalog.bundled()
        let lateral = try XCTUnwrap(catalog.item("dumbbell-lateral"))
        let choices = catalog.alternatives(to: lateral, equipment: ["cable"])
        XCTAssertEqual(choices.map(\.id), ["cable-lateral"])
        XCTAssertTrue(choices.allSatisfy { $0.primary.contains(.sideDelts) && $0.pattern == lateral.pattern })
        XCTAssertFalse(catalog.alternatives(to: lateral).contains { $0.id == "dumbbell-press" })
    }
    func testTemplateInstallCreatesFreshDaysAndKeepsExistingLibrary() throws {
        let store = try store(); let catalog = try ExerciseCatalog.bundled(); let template = TrainingTemplate.all[0]
        let previousIDs = Set(try store.context.fetch(FetchDescriptor<TrainingPlan>()).map(\.id))
        try template.install(catalog: catalog, equipment: Set(ExerciseCatalog.equipmentNames.keys), selections: [:], priority: .sideDelts,
            name: "我的三分化", weeklySessions: 4, context: store.context)
        let parent = try XCTUnwrap(store.context.fetch(FetchDescriptor<TrainingProgram>()).first { $0.name == "我的三分化" })
        XCTAssertEqual(parent.weeklySessions, 4)
        let days = try store.context.fetch(FetchDescriptor<TrainingPlan>())
        XCTAssertTrue(previousIDs.isSubset(of: Set(days.map(\.id))))
        XCTAssertEqual(days.filter { $0.programID == parent.id }.count, 3)
    }
    func testUnavailableEquipmentAndFailedTemplateCommitLeaveLibraryUnchanged() throws {
        let store = try store(); let catalog = try ExerciseCatalog.bundled(); let template = TrainingTemplate.all[1]
        let initial = Set(try store.context.fetch(FetchDescriptor<TrainingPlan>()).map(\.id))
        XCTAssertThrowsError(try template.install(catalog: catalog, equipment: [], selections: [:], priority: nil, name: "不可用", context: store.context))
        XCTAssertThrowsError(try template.install(catalog: catalog, equipment: Set(ExerciseCatalog.equipmentNames.keys), selections: [:], priority: nil,
            name: "失败", context: store.context, beforeCommit: { throw TimerFailure.denied }))
        XCTAssertEqual(Set(try store.context.fetch(FetchDescriptor<TrainingPlan>()).map(\.id)), initial)
        XCTAssertFalse(store.context.hasChanges)
    }
    func testPriorityOrderIsStableAndLeavesUnlinkedCustomSlotInPlace() throws {
        let catalog = try ExerciseCatalog.bundled()
        let press = try XCTUnwrap(catalog.item("dumbbell-press")).spec()
        let rear = try XCTUnwrap(catalog.item("dumbbell-rear")).spec()
        let side = try XCTUnwrap(catalog.item("dumbbell-lateral")).spec()
        let custom = ExerciseSpec(name: "自定义")
        let advice = TrainingOrderAdvice.suggest([press, custom, rear, side], catalog: catalog, priority: .sideDelts)
        XCTAssertEqual(advice.map(\.exercise.id), [side.id, custom.id, press.id, rear.id])
        XCTAssertTrue(advice[0].reason.contains("肩中束"))
        XCTAssertEqual(TrainingOrderAdvice.suggest([side, rear], catalog: catalog, priority: nil).map(\.exercise.id), [side.id, rear.id])
    }
    func testActualSetValuesRemainImmutableWhenNextSetChanges() async throws {
        let f = try await fixture([ExerciseSpec(name: "卧推", sets: 2, catalogID: "barbell-bench")])
        let first = SetValues(weight: 40, repetitions: 10)
        await f.controller.setValues(first, interactionID: f.controller.session?.interactionID)
        await f.controller.completeSet()
        let second = SetValues(weight: 45, repetitions: 8)
        await f.controller.setValues(second, interactionID: f.controller.session?.interactionID)
        XCTAssertEqual(f.controller.session?.performances?.first?.first?.values, first)
        await f.controller.skipRest(); f.clock.now.addTimeInterval(1)
        await f.controller.completeSet()
        let record = try XCTUnwrap(f.store.context.fetch(FetchDescriptor<TrainingRecord>()).first)
        XCTAssertEqual(try record.performances()?.first?.map(\.values), [first, second])
    }
    func testLockScreenCompletesWithCurrentValuesExactlyOnce() async throws {
        let f = try await fixture([ExerciseSpec(name: "哑铃弯举", sets: 2)])
        let values = SetValues(weight: 12.5, repetitions: 12, kind: .perHand)
        await f.controller.setValues(values, interactionID: f.controller.session?.interactionID)
        let token = try XCTUnwrap(f.controller.session?.interactionID).uuidString
        await f.controller.handleQuickAction(.completeSet, interactionID: token)
        await f.controller.handleQuickAction(.completeSet, interactionID: token)
        XCTAssertEqual(f.controller.session?.performances?.first?.count, 1)
        XCTAssertEqual(f.controller.session?.performances?.first?.first?.values, values)
    }
    func testAlternativeDoesNotInheritUnrelatedLoadAndRecordsActualVariant() async throws {
        let alternative = ExerciseAlternative(name: "哑铃卧推", catalogID: "dumbbell-bench", prescription: SetValues(repetitions: 10, kind: .perHand))
        let f = try await fixture([ExerciseSpec(name: "卧推", sets: 2, alternatives: [alternative], catalogID: "barbell-bench", prescription: SetValues(weight: 60, repetitions: 8))])
        await f.controller.completeSet(); await f.controller.skipRest(); f.clock.now.addTimeInterval(1)
        await f.controller.selectAlternative(alternative.id)
        XCTAssertNil(f.controller.session?.currentSetValues.weight)
        XCTAssertEqual(f.controller.session?.currentSetValues.kind, .perHand)
        await f.controller.setValues(SetValues(weight: 20, repetitions: 10, kind: .perHand), interactionID: f.controller.session?.interactionID)
        await f.controller.completeSet()
        let record = try XCTUnwrap(f.store.context.fetch(FetchDescriptor<TrainingRecord>()).first)
        let sets = try XCTUnwrap(record.performances()?.first)
        XCTAssertEqual(sets.map(\.catalogID), ["barbell-bench", "dumbbell-bench"])
        XCTAssertEqual(sets.map { $0.values?.weight }, [60, 20])
    }
    func testColdRestoreKeepsDraftAndCompletedMetrics() async throws {
        let f = try await fixture([ExerciseSpec(name: "划船", sets: 3)])
        let original = SetValues(weight: 30, repetitions: 10, kind: .machine, equipmentNote: "器械A")
        await f.controller.setValues(original, interactionID: f.controller.session?.interactionID)
        await f.controller.completeSet()
        let restored = try TrainingController(store: f.store, alarm: f.timer, notification: f.timer)
        XCTAssertEqual(restored.session?.currentSetValues, original)
        XCTAssertEqual(restored.session?.performances?.first?.first?.values, original)
    }
    func testLegacyCompletedSetsAreUnknownRatherThanInventedWeights() throws {
        var session = try TrainingSession(planID: UUID(), planName: "旧记录", exercises: [ExerciseSpec(name: "动作", sets: 3)], fallback: false)
        session.completed = [1]; session.performedNames = [["旧动作"]]
        let restored = try JSONDecoder().decode(TrainingSession.self, from: JSONEncoder().encode(session))
        var migrated = restored; migrated.preparePerformanceStorage()
        XCTAssertNil(migrated.performances?.first?.first?.values)
        XCTAssertNil(migrated.performances?.first?.first?.profileKey)
        XCTAssertEqual(migrated.performances?.first?.first?.exerciseName, "旧动作")
    }
    func testInvalidMeasurementsAndUnconfirmedDraftDoNotChangeProgress() async throws {
        let f = try await fixture([ExerciseSpec(name: "动作", sets: 2)])
        let id = f.controller.session?.interactionID
        for values in [SetValues(weight: -.infinity), SetValues(weight: .nan), SetValues(repetitions: 0), SetValues(weight: 20, kind: .bodyweight), SetValues(unit: .level)] {
            await f.controller.setValues(values, interactionID: id)
            XCTAssertEqual(f.controller.session?.completedSets, 0)
            XCTAssertEqual(f.controller.session?.interactionID, id)
            XCTAssertNotNil(f.controller.error)
        }
        XCTAssertNil(f.controller.session?.performances)
    }
    func testRemainingReorderPreservesCompletedNamesAndDraftAlignment() async throws {
        let a = ExerciseSpec(name: "A", sets: 2), b = ExerciseSpec(name: "B", sets: 1, prescription: SetValues(weight: 20)), c = ExerciseSpec(name: "C", sets: 1, prescription: SetValues(weight: 30))
        let f = try await fixture([a, b, c])
        await f.controller.completeSet(); await f.controller.skipRest()
        let measured = f.controller.session?.performances?.first
        await f.controller.reorderRemaining([c.id, b.id], interactionID: f.controller.session?.interactionID)
        XCTAssertEqual(f.controller.session?.exercises.map(\.name), ["A", "C", "B"])
        XCTAssertEqual(f.controller.session?.performances?.first, measured)
        XCTAssertEqual(f.controller.session?.setDrafts?.map(\.weight), [nil, 30, 20])
        XCTAssertEqual(f.controller.session?.completedSets, 1)
        XCTAssertNil(f.controller.error)
    }
    func testStaleReorderCannotOverwriteNewerProgress() async throws {
        let a = ExerciseSpec(name: "A", sets: 2), b = ExerciseSpec(name: "B", sets: 1)
        let f = try await fixture([a, b]); let old = f.controller.session?.interactionID
        await f.controller.setValues(SetValues(weight: 25), interactionID: old)
        await f.controller.reorderRemaining([b.id, a.id], interactionID: old)
        XCTAssertEqual(f.controller.session?.exercises.map(\.id), [a.id, b.id])
        XCTAssertEqual(f.controller.session?.currentSetValues.weight, 25)
        XCTAssertNotNil(f.controller.error)
    }
    func testVersionThreeRoundTripPreservesCatalogPrescriptionsAndFrequency() throws {
        let partial = try JSONDecoder().decode(SetValues.self, from: Data(#"{"weight":12.5}"#.utf8))
        XCTAssertEqual(partial.unit, .kg); XCTAssertEqual(partial.kind, .total)
        XCTAssertNil(partial.repetitions)
        let store = try store(); let catalog = try ExerciseCatalog.bundled()
        try TrainingTemplate.all[0].install(catalog: catalog, equipment: Set(ExerciseCatalog.equipmentNames.keys), selections: [:], priority: nil,
            name: "导出三分化", weeklySessions: 4, context: store.context)
        let programs = try store.context.fetch(FetchDescriptor<TrainingProgram>())
        let days = try store.context.fetch(FetchDescriptor<TrainingPlan>())
        let archive = try PlanArchive.decode(PlanArchive.export(plans: days, programs: programs))
        XCTAssertEqual(archive.version, 3)
        XCTAssertTrue(archive.programs?.contains { $0.weeklySessions == 4 } ?? false)
        let entry = try XCTUnwrap(archive.plans.first { $0.exercises.contains { $0.catalogID != nil } })
        XCTAssertNotNil(entry.exercises.first?.prescription?.repetitions)
        try archive.append(to: store.context)
        XCTAssertEqual(try store.context.fetch(FetchDescriptor<TrainingPlan>()).count, days.count * 2)
    }
    func testHistoryPrefillUsesMatchingEquipmentAndPreservesExplicitPlanFields() async throws {
        let base = ExerciseSpec(name: "器械划船", sets: 1, catalogID: "machine-row", prescription: SetValues(repetitions: 12, kind: .machine, equipmentNote: "A"))
        let f = try await fixture([base])
        let actual = SetValues(weight: 40, repetitions: 8, kind: .machine, equipmentNote: "A")
        await f.controller.setValues(actual, interactionID: f.controller.session?.interactionID); await f.controller.completeSet()
        let suggested = try f.store.suggestedValues(for: base)
        XCTAssertEqual(suggested.weight, 40); XCTAssertEqual(suggested.repetitions, 12)
        var different = base; different.prescription?.equipmentNote = "B"
        XCTAssertNil(try f.store.suggestedValues(for: different).weight)
        different = base; different.prescription?.unit = .lb
        XCTAssertNil(try f.store.suggestedValues(for: different).weight)
    }
    func testChangingPrescriptionDoesNotRewriteAlreadySavedRecord() async throws {
        let original = ExerciseSpec(name: "动作", sets: 1, prescription: SetValues(weight: 35, repetitions: 10))
        let f = try await fixture([original]); await f.controller.completeSet()
        var edited = original; edited.prescription = SetValues(weight: 50, repetitions: 6)
        try PlanEditing.save([edited], to: f.day, context: f.store.context)
        let record = try XCTUnwrap(f.store.context.fetch(FetchDescriptor<TrainingRecord>()).first)
        XCTAssertEqual(try record.performances()?.first?.first?.values?.weight, 35)
        XCTAssertEqual(try record.exercises().first?.prescription?.weight, 35)
        XCTAssertEqual(try f.day.exercises().first?.prescription?.weight, 50)
    }
    private func writeDiskPerformance(at url: URL) throws -> UUID {
        let container = try ModelContainer(for: TrainingProgram.self, TrainingPlan.self, LibraryPreferences.self, ActiveTraining.self, TrainingRecord.self,
            configurations: ModelConfiguration(url: url))
        let store = try TrainingStore(container: container)
        let values = SetValues(weight: 22.5, repetitions: 9, kind: .perHand)
        let exercise = ExerciseSpec(name: "哑铃卧推", sets: 1, catalogID: "dumbbell-bench", prescription: values)
        var session = try TrainingSession(planID: UUID(), planName: "磁盘记录", exercises: [exercise], fallback: false)
        session.completed = [1]; session.performedNames = [[exercise.name]]; session.phase = .completed
        session.performances = [[SetPerformance(exerciseName: exercise.name, catalogID: exercise.catalogID, values: values,
            profileKey: exercise.profileKey(for: values), completedAt: Date())]]
        try store.save(session)
        return try XCTUnwrap(session.sessionID)
    }
    func testSetMeasurementsSurviveDiskContainerReopen() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("training.store")
        let id = try writeDiskPerformance(at: url)
        let reopened = try TrainingStore(container: ModelContainer(for: TrainingProgram.self, TrainingPlan.self, LibraryPreferences.self, ActiveTraining.self, TrainingRecord.self,
            configurations: ModelConfiguration(url: url)))
        let record = try XCTUnwrap(reopened.context.fetch(FetchDescriptor<TrainingRecord>()).first { $0.id == id })
        XCTAssertEqual(try record.performances()?.first?.first?.values?.weight, 22.5)
        XCTAssertEqual(try record.performances()?.first?.first?.values?.repetitions, 9)
        XCTAssertEqual(try record.performances()?.first?.first?.values?.kind, .perHand)
    }

}
