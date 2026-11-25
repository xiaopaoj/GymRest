import XCTest
import SwiftData
@testable import GymRest

@MainActor final class ReplacementImportTests: XCTestCase {
    private struct Fixture {
        let store: TrainingStore
        let first: TrainingProgram
        let other: TrainingProgram
        let days: [TrainingPlan]
    }
    private func fixture() throws -> Fixture {
        let container = try ModelContainer(for: TrainingProgram.self, TrainingPlan.self, LibraryPreferences.self, ActiveTraining.self, TrainingRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = try TrainingStore(container: container); let context = store.context
        for day in try context.fetch(FetchDescriptor<TrainingPlan>()) { context.delete(day) }
        for program in try context.fetch(FetchDescriptor<TrainingProgram>()) { context.delete(program) }
        try context.save()
        let first = TrainingProgram(name: "五分化", position: 0)
        let other = TrainingProgram(name: "其他计划", position: 1)
        context.insert(first); context.insert(other)
        var days: [TrainingPlan] = []
        for (index, name) in ["周一", "周二", "其他训练", "未归类训练"].enumerated() {
            let day = try TrainingPlan(name: name, position: index, exercises: [ExerciseSpec(name: "原动作", sets: 2)])
            day.programID = index < 2 ? first.id : index == 2 ? other.id : nil
            context.insert(day); days.append(day)
        }
        try context.save()
        return Fixture(store: store, first: first, other: other, days: days)
    }
    private func archive() -> PlanArchive {
        PlanArchive(plans: [.init(id: UUID(), name: "更新后的周一",
            exercises: [ExerciseSpec(name: "新动作", restSeconds: 47, transitionRestSeconds: 180)])])
    }
    func testSelectedReplacementPreservesOtherProgramsAndUnclassifiedDays() throws {
        let f = try fixture(); let source = archive(); let context = f.store.context
        let preview = try source.previewReplacement(in: context, scope: .program(f.first.id))
        XCTAssertEqual(preview.days.count, 2)
        try source.replace(in: context, confirmed: preview)
        let days = try context.fetch(FetchDescriptor<TrainingPlan>())
        XCTAssertEqual(days.count, 3)
        XCTAssertTrue(days.contains { $0.id == f.days[2].id })
        XCTAssertTrue(days.contains { $0.id == f.days[3].id })
        let imported = try XCTUnwrap(days.first { $0.programID == f.first.id })
        XCTAssertEqual(imported.name, "更新后的周一")
        XCTAssertEqual(try imported.exercises().first?.transitionRestSeconds, 180)
        XCTAssertNotEqual(imported.id, source.plans[0].id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TrainingProgram>()).count, 2)
    }
    func testWholeLibraryReplacementPreservesIncomingGroupingAndOrder() throws {
        let f = try fixture(); let parentID = UUID()
        let originalIDs = Set(f.days.map(\.id))
        let source = PlanArchive(version: 2, plans: [
            .init(id: UUID(), name: "新周一", exercises: [], programID: parentID),
            .init(id: UUID(), name: "新周二", exercises: [], programID: parentID)
        ], programs: [.init(id: parentID, name: "新计划")])
        let preview = try source.previewReplacement(in: f.store.context, scope: .library)
        try source.replace(in: f.store.context, confirmed: preview)
        let parents = try f.store.context.fetch(FetchDescriptor<TrainingProgram>())
        XCTAssertEqual(parents.count, 1); XCTAssertEqual(parents.first?.name, "新计划")
        let days = try f.store.context.fetch(FetchDescriptor<TrainingPlan>(sortBy: [SortDescriptor(\TrainingPlan.position)]))
        XCTAssertEqual(days.map(\.name), ["新周一", "新周二"])
        XCTAssertTrue(days.allSatisfy { $0.programID == parents.first?.id })
        XCTAssertFalse(days.contains { originalIDs.contains($0.id) })
    }
    func testGroupedFileFlattensOnlyIntoExplicitSelectedProgram() throws {
        let f = try fixture(); let parent = UUID()
        let source = PlanArchive(version: 2, plans: [.init(id: UUID(), name: "导入训练", exercises: [], programID: parent)],
                                 programs: [.init(id: parent, name: "文件分组")])
        let preview = try source.previewReplacement(in: f.store.context, scope: .program(f.first.id))
        try source.replace(in: f.store.context, confirmed: preview)
        XCTAssertEqual(f.first.name, "五分化")
        XCTAssertFalse(try f.store.context.fetch(FetchDescriptor<TrainingProgram>()).contains { $0.name == "文件分组" })
        XCTAssertEqual(try f.store.context.fetch(FetchDescriptor<TrainingPlan>()).filter { $0.programID == f.first.id }.count, 1)
    }
    func testReplacementPreservesActiveSnapshotHistoryAndHealthAssociation() throws {
        let f = try fixture(); let source = archive(); let context = f.store.context
        let day = f.days[0]
        var completed = try TrainingSession(planID: day.id, planName: day.name, exercises: day.exercises(), fallback: false)
        completed.completed = [2]; completed.performedNames = [["原动作", "原动作"]]; completed.phase = .completed
        try f.store.save(completed)
        let record = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingRecord>()).first)
        let recordID = record.id; let workoutID = UUID().uuidString
        record.workoutID = workoutID; try context.save()
        let active = try TrainingSession(planID: day.id, planName: day.name, exercises: day.exercises(), fallback: false)
        try f.store.save(active)
        let preview = try source.previewReplacement(in: context, scope: .library)
        try source.replace(in: context, confirmed: preview, newProgramName: "导入计划")
        XCTAssertEqual(try f.store.load(), active)
        let records = try context.fetch(FetchDescriptor<TrainingRecord>())
        XCTAssertEqual(records.count, 1); XCTAssertEqual(records.first?.id, recordID)
        XCTAssertEqual(records.first?.workoutID, workoutID)
        XCTAssertEqual(try records.first?.exercises().first?.name, "原动作")
    }
    func testFailedReplacementRestoresOriginalIDsAndContents() throws {
        let f = try fixture(); let source = archive(); let context = f.store.context
        let preview = try source.previewReplacement(in: context, scope: .library)
        XCTAssertThrowsError(try source.replace(in: context, confirmed: preview, newProgramName: "导入计划",
            beforeCommit: { throw TimerFailure.denied }))
        XCTAssertEqual(try source.previewReplacement(in: context, scope: .library), preview)
        XCTAssertFalse(context.hasChanges)
        let independent = ModelContext(context.container)
        XCTAssertEqual(Set(try independent.fetch(FetchDescriptor<TrainingPlan>()).map(\.id)), Set(f.days.map(\.id)))
    }
    func testConfirmedPreviewRejectsSubsequentLocalEdits() throws {
        let f = try fixture(); let source = archive(); let context = f.store.context
        let preview = try source.previewReplacement(in: context, scope: .program(f.first.id))
        f.days[0].name = "确认后修改"; try context.save()
        XCTAssertThrowsError(try source.replace(in: context, confirmed: preview))
        XCTAssertEqual(try context.fetch(FetchDescriptor<TrainingPlan>()).count, 4)
        XCTAssertEqual(f.days[0].name, "确认后修改")
    }
    func testUnrelatedSavedEditDoesNotInvalidateSelectedScope() throws {
        let f = try fixture(); let source = archive(); let context = f.store.context
        let preview = try source.previewReplacement(in: context, scope: .program(f.first.id))
        f.days[2].name = "其他计划的更新"; try context.save()
        try source.replace(in: context, confirmed: preview)
        XCTAssertEqual(f.days[2].name, "其他计划的更新")
    }
    func testInvalidOrEmptyFileAndMissingTargetCannotStartReplacement() throws {
        let f = try fixture(); let context = f.store.context
        XCTAssertThrowsError(try PlanArchive(plans: []).previewReplacement(in: context, scope: .library))
        XCTAssertThrowsError(try archive().previewReplacement(in: context, scope: .program(UUID())))
        var bad = archive(); bad.plans[0].exercises[0].transitionRestSeconds = -1
        XCTAssertThrowsError(try bad.previewReplacement(in: context, scope: .library))
        XCTAssertEqual(try context.fetch(FetchDescriptor<TrainingPlan>()).count, 4)
    }
    func testDefaultAppendStillCreatesCopiesWithoutReplacingExistingDays() throws {
        let f = try fixture(); let source = archive(); let context = f.store.context
        try source.append(to: context, targetProgram: f.first)
        try source.append(to: context, targetProgram: f.first)
        let days = try context.fetch(FetchDescriptor<TrainingPlan>())
        XCTAssertEqual(days.count, 6)
        XCTAssertTrue(Set(f.days.map(\.id)).isSubset(of: Set(days.map(\.id))))
    }
    func testConfirmedPreviewCannotBeReusedForAnotherFile() throws {
        let f = try fixture(); let source = archive(); let context = f.store.context
        let preview = try source.previewReplacement(in: context, scope: .library)
        var changed = source; changed.plans[0].name = "另一份文件"
        XCTAssertThrowsError(try changed.replace(in: context, confirmed: preview))
        XCTAssertEqual(try context.fetch(FetchDescriptor<TrainingPlan>()).count, 4)
    }
    func testUnsavedLocalEditsAreNeitherCommittedNorDiscardedByReplacement() throws {
        let f = try fixture(); let source = archive(); let context = f.store.context
        let preview = try source.previewReplacement(in: context, scope: .library)
        f.days[0].name = "未保存的草稿"
        XCTAssertThrowsError(try source.replace(in: context, confirmed: preview))
        XCTAssertEqual(f.days[0].name, "未保存的草稿")
        XCTAssertTrue(context.hasChanges)
        context.discardPendingChanges()
    }
}
