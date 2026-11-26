import XCTest
import SwiftData
@testable import GymRest

@MainActor final class LegacyPlaceholderTests: XCTestCase {
    private let names = ["胸部训练", "背部训练", "腿部训练", "肩部训练", "手臂训练"]
    private func container(_ url: URL? = nil) throws -> ModelContainer {
        let config = url.map { ModelConfiguration(url: $0) } ?? ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: TrainingProgram.self, TrainingPlan.self, LibraryPreferences.self, ActiveTraining.self, TrainingRecord.self,
                                  configurations: config)
    }
    private func seed(in context: ModelContext, parent: TrainingProgram? = nil) throws {
        for (i, name) in names.enumerated() {
            let day = try TrainingPlan(name: name, position: i)
            day.programID = parent?.id; context.insert(day)
        }
    }
    func testUpgradeRemovesUnassignedSeedsAndPreservesUserDataAndSnapshots() throws {
        let c = try container(); let context = ModelContext(c)
        let prefs = LibraryPreferences(); prefs.legacyPlaceholdersRemoved = nil
        context.insert(prefs); try seed(in: context)
        let custom = try TrainingPlan(name: "我的空白日", position: 9)
        let populated = try TrainingPlan(name: "胸部训练", position: 10, exercises: [ExerciseSpec(name: "卧推")])
        let corrupt = try TrainingPlan(name: "背部训练", position: 11); corrupt.exerciseData = Data("broken".utf8)
        let parent = TrainingProgram(name: "我的五分化", position: 0); context.insert(parent)
        let grouped = try TrainingPlan(name: "腿部训练", position: 12); grouped.programID = parent.id
        for day in [custom, populated, corrupt, grouped] { context.insert(day) }
        var session = try TrainingSession(planID: populated.id, planName: populated.name, exercises: populated.exercises(), fallback: false)
        let activePayload = try JSONEncoder().encode(session)
        context.insert(ActiveTraining(payload: activePayload))
        session.phase = .completed
        let record = try TrainingRecord(session: session, end: Date()); record.workoutID = "health-link"
        context.insert(record); try context.save()
        let store = try TrainingStore(container: c)
        let remaining = try store.context.fetch(FetchDescriptor<TrainingPlan>())
        XCTAssertEqual(Set(remaining.map(\.id)), Set([custom.id, populated.id, corrupt.id, grouped.id]))
        XCTAssertEqual(try store.context.fetch(FetchDescriptor<ActiveTraining>()).first?.payload, activePayload)
        XCTAssertEqual(try store.context.fetch(FetchDescriptor<TrainingRecord>()).first?.workoutID, "health-link")
        XCTAssertEqual(store.preferences.legacyPlaceholdersRemoved, true)
        let laterBlank = try TrainingPlan(name: "胸部训练", position: 20)
        store.context.insert(laterBlank); try store.context.save()
        let reopened = try TrainingStore(container: c)
        XCTAssertTrue(try reopened.context.fetch(FetchDescriptor<TrainingPlan>()).contains { $0.id == laterBlank.id })
    }
    func testDefaultContainerIsDeletedOnlyWhenNoChildrenRemain() throws {
        let store = try TrainingStore(container: container()); let context = store.context
        let empty = TrainingProgram(name: "五分化模板", position: 0)
        let used = TrainingProgram(name: "五分化模板", position: 1)
        context.insert(empty); context.insert(used)
        try seed(in: context, parent: empty); try seed(in: context, parent: used)
        let real = try TrainingPlan(name: "自定义", position: 20, exercises: [ExerciseSpec(name: "深蹲")])
        real.programID = used.id; context.insert(real)
        store.preferences.legacyPlaceholdersRemoved = nil; try context.save()
        try TrainingStore.removeLegacyPlaceholders(in: context, preferences: store.preferences)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TrainingProgram>()).map(\.id), [used.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<TrainingPlan>()).map(\.id), [real.id])
    }
    func testCleanupFailureRollsBackRowsAndMarkerAndCanRetry() throws {
        let store = try TrainingStore(container: container()); let context = store.context
        try seed(in: context); store.preferences.legacyPlaceholdersRemoved = nil; try context.save()
        XCTAssertThrowsError(try TrainingStore.removeLegacyPlaceholders(in: context, preferences: store.preferences,
                                                                       beforeCommit: { throw TimerFailure.denied }))
        XCTAssertEqual(try context.fetch(FetchDescriptor<TrainingPlan>()).count, 5)
        XCTAssertNil(store.preferences.legacyPlaceholdersRemoved)
        XCTAssertFalse(context.hasChanges)
        try TrainingStore.removeLegacyPlaceholders(in: context, preferences: store.preferences)
        XCTAssertTrue(try context.fetch(FetchDescriptor<TrainingPlan>()).isEmpty)
    }
    private func writeOldLibrary(_ url: URL) throws {
        let context = ModelContext(try container(url))
        let prefs = LibraryPreferences(); prefs.legacyPlaceholdersRemoved = nil
        context.insert(prefs); try seed(in: context); try context.save()
    }
    private func migrateAndAddBlank(_ url: URL) throws {
        let store = try TrainingStore(container: container(url))
        XCTAssertTrue(try store.context.fetch(FetchDescriptor<TrainingPlan>()).isEmpty)
        store.context.insert(try TrainingPlan(name: "胸部训练", position: 0)); try store.context.save()
    }
    func testCleanupAndOneTimeMarkerPersistAcrossDiskReopen() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("legacy.store")
        try writeOldLibrary(url); try migrateAndAddBlank(url)
        let reopened = try TrainingStore(container: container(url))
        XCTAssertEqual(reopened.preferences.legacyPlaceholdersRemoved, true)
        XCTAssertEqual(try reopened.context.fetch(FetchDescriptor<TrainingPlan>()).count, 1)
    }
}
