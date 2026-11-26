import XCTest
import SwiftData
@testable import GymRest

@MainActor final class ProgramLibraryTests: XCTestCase {
    private func store() throws -> TrainingStore {
        let container = try ModelContainer(for: TrainingProgram.self, TrainingPlan.self, LibraryPreferences.self, ActiveTraining.self, TrainingRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return try TrainingStore(container: container)
    }
    func testFreshLibraryDoesNotCreateEmptyProgramOrDays() throws {
        let store = try store()
        let programs = try store.context.fetch(FetchDescriptor<TrainingProgram>())
        let days = try store.context.fetch(FetchDescriptor<TrainingPlan>())
        XCTAssertTrue(programs.isEmpty); XCTAssertTrue(days.isEmpty)
    }
    func testConvertBlankContainerAndGroupWithoutChangingExercises() throws {
        let store = try store(); let context = store.context
        let blank = try TrainingPlan(name: "我的五分化", position: 9)
        let day = try TrainingPlan(name: "周一", position: 10, exercises: [ExerciseSpec(name: "卧推")])
        context.insert(blank); context.insert(day); try context.save()
        let original = day.exerciseData; let id = blank.id
        try ProgramLibrary.organize(name: blank.name, days: [day], existing: nil, convertBlank: blank, context: context)
        XCTAssertEqual(day.programID, id); XCTAssertEqual(day.exerciseData, original)
        XCTAssertFalse(try context.fetch(FetchDescriptor<TrainingPlan>()).contains(where: { $0.id == id }))
        XCTAssertTrue(try context.fetch(FetchDescriptor<TrainingProgram>()).contains(where: { $0.id == id }))
    }
    func testNonemptyDayCannotBeConvertedOrDeletedAsContainer() throws {
        let store = try store(); let context = store.context
        let day = try TrainingPlan(name: "非空", position: 10, exercises: [ExerciseSpec(name: "卧推")])
        context.insert(day); try context.save()
        XCTAssertThrowsError(try ProgramLibrary.organize(name: "计划", days: [], existing: nil, convertBlank: day, context: context))
        XCTAssertNotNil(day.modelContext)
        XCTAssertEqual(try day.exercises().count, 1)
    }
    func testVersionTwoExportImportPreservesGroupingAndOrder() throws {
        let store = try store(); let context = store.context
        let parent = TrainingProgram(name: "导出测试", position: 10); context.insert(parent)
        let first = try TrainingPlan(name: "周一", position: 0)
        let second = try TrainingPlan(name: "周二", position: 1)
        first.programID = parent.id; second.programID = parent.id
        context.insert(first); context.insert(second); try context.save()
        let archive = try PlanArchive.decode(PlanArchive.export(plans: [first, second], programs: [parent]))
        XCTAssertEqual(archive.version, 2)
        try archive.append(to: context)
        let importedParent = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingProgram>()).first(where: { $0.name == parent.name && $0.id != parent.id }))
        let imported = try context.fetch(FetchDescriptor<TrainingPlan>(sortBy: [SortDescriptor(\TrainingPlan.position)])).filter { $0.programID == importedParent.id }
        XCTAssertEqual(imported.map(\.name), ["周一", "周二"])
    }
    func testLegacyImportTargetsSelectedProgramAndDoesNotDuplicateIt() throws {
        let store = try store(); let context = store.context
        let parent = TrainingProgram(name: "测试计划", position: 0)
        context.insert(parent); try context.save()
        let archive = PlanArchive(plans: [.init(id: UUID(), name: "导入周一", exercises: [])])
        try archive.append(to: context, targetProgram: parent)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TrainingProgram>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TrainingPlan>()).first(where: { $0.name == "导入周一" })?.programID, parent.id)
    }
    func testRemovingProgramPreservesDays() throws {
        let store = try store(); let context = store.context
        let parent = TrainingProgram(name: "测试计划", position: 0)
        context.insert(parent); try context.save()
        for i in 0..<5 {
            let day = try TrainingPlan(name: "训练日\(i)", position: i)
            day.programID = parent.id; context.insert(day)
        }
        try context.save()
        try ProgramLibrary.detachAndDelete(parent, context: context)
        let days = try context.fetch(FetchDescriptor<TrainingPlan>())
        XCTAssertEqual(days.count, 5); XCTAssertTrue(days.allSatisfy { $0.programID == nil })
    }
    func testStartIsNotBlockedBySuspendedBackgroundAuthorizationQuery() async throws {
        let store = try store(); let timer = MockTimerService()
        var continuation: CheckedContinuation<Void, Never>?
        timer.onAuthorization = { await withCheckedContinuation { continuation = $0 } }
        let controller = try TrainingController(store: store, alarm: timer, notification: timer)
        let day = try TrainingPlan(name: "周一", position: 0, exercises: [ExerciseSpec(name: "卧推")])
        let background = Task { await controller.reconcile() }
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        guard let resume = continuation else { background.cancel(); XCTFail("Background query did not begin"); return }
        XCTAssertFalse(controller.busy)
        await controller.start(plan: day)
        XCTAssertEqual(controller.session?.planID, day.id)
        XCTAssertEqual(controller.session?.phase, .training)
        resume.resume(); await background.value
        XCTAssertEqual(controller.session?.planID, day.id)
        XCTAssertNil(controller.error)
    }
}
