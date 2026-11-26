import XCTest
import SwiftData
@testable import GymRest

@MainActor final class DiskPersistenceTests: XCTestCase {
    private struct SavedIDs {
        let parent: UUID
        let day: UUID
        let record: UUID
        let workout: String
    }
    private func open(_ url: URL) throws -> TrainingStore {
        try TrainingStore(container: ModelContainer(for: TrainingProgram.self, TrainingPlan.self, LibraryPreferences.self, ActiveTraining.self, TrainingRecord.self,
            configurations: ModelConfiguration(url: url)))
    }
    private func location() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GymRest-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("history.store")
    }
    private func writeHistory(_ url: URL) throws -> SavedIDs {
        let store = try open(url); let context = store.context
        let parent = TrainingProgram(name: "我的计划", position: 0)
        let day = try TrainingPlan(name: "周一", position: 0)
        day.programID = parent.id; context.insert(parent); context.insert(day)
        try day.setExercises([ExerciseSpec(name: "卧推", sets: 2, restSeconds: 47)])
        store.preferences.defaultRest = 47; try context.save()
        var session = try TrainingSession(planID: day.id, planName: day.name, exercises: day.exercises(), fallback: false)
        session.completed = [2]; session.performedNames = [["卧推", "卧推"]]; session.phase = .completed
        try store.save(session)
        let record = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingRecord>()).first)
        let workoutID = UUID().uuidString
        record.workoutID = workoutID; record.workoutSource = "测试运动来源"
        record.workoutStart = session.startedAt; record.workoutEnd = record.endedAt
        try context.save()
        return SavedIDs(parent: parent.id, day: day.id, record: record.id, workout: workoutID)
    }
    func testHistoryPlansPreferencesAndAssociationSurviveContainerReopen() throws {
        let url = try location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let ids = try writeHistory(url)
        let reopened = try open(url); let context = reopened.context
        let records = try context.fetch(FetchDescriptor<TrainingRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].id, ids.record)
        XCTAssertEqual(try records[0].completed(), [2])
        XCTAssertEqual(records[0].workoutID, ids.workout)
        XCTAssertEqual(records[0].workoutSource, "测试运动来源")
        XCTAssertEqual(reopened.preferences.defaultRest, 47)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TrainingProgram>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TrainingPlan>()).count, 1)
        let day = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingPlan>()).first { $0.id == ids.day })
        XCTAssertEqual(day.programID, ids.parent)
        XCTAssertEqual(try day.exercises().first?.restSeconds, 47)
        XCTAssertNil(try reopened.load())
    }
    private func attemptFailedEdit(_ url: URL, ids: SavedIDs) throws {
        let store = try open(url); let context = store.context
        let day = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingPlan>()).first { $0.id == ids.day })
        let originalData = day.exerciseData
        XCTAssertThrowsError(try PlanEditing.save([ExerciseSpec(name: "失败草稿", restSeconds: 120)], to: day, context: context,
            beforeCommit: { throw TimerFailure.denied }))
        XCTAssertEqual(day.exerciseData, originalData)
        XCTAssertFalse(context.hasChanges)
    }
    func testFailedEditLeavesDiskPlanAndHistoryUnchangedAfterReopen() throws {
        let url = try location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let ids = try writeHistory(url); try attemptFailedEdit(url, ids: ids)
        let reopened = try open(url)
        let day = try XCTUnwrap(reopened.context.fetch(FetchDescriptor<TrainingPlan>()).first { $0.id == ids.day })
        XCTAssertEqual(try day.exercises().first?.name, "卧推")
        XCTAssertEqual(try day.exercises().first?.restSeconds, 47)
        let record = try XCTUnwrap(reopened.context.fetch(FetchDescriptor<TrainingRecord>()).first)
        XCTAssertEqual(record.id, ids.record)
        XCTAssertEqual(record.workoutID, ids.workout)
    }
    private func writeActive(_ url: URL) throws -> TrainingSession {
        let ids = try writeHistory(url)
        let store = try open(url)
        var session = try TrainingSession(planID: ids.day, planName: "周一", exercises: [ExerciseSpec(name: "卧推", sets: 3, restSeconds: 60)], fallback: false)
        session.completed = [1]; session.performedNames = [["卧推"]]; session.phase = .resting
        session.originalRest = 60; session.remaining = 60
        session.timerID = UUID(); session.restEnd = Date().addingTimeInterval(60); session.reminderRegistered = true
        try store.save(session); return session
    }
    func testActiveProgressAndHistoryCoexistAfterReopeningDiskStore() throws {
        let url = try location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let saved = try writeActive(url)
        let reopened = try open(url)
        XCTAssertEqual(try reopened.load(), saved)
        XCTAssertEqual(try reopened.context.fetch(FetchDescriptor<TrainingRecord>()).count, 1)
        // This verifies the saved identifier only, not that a real system alarm exists.
    }
    private func deleteSource(_ url: URL, ids: SavedIDs) throws {
        let store = try open(url); let context = store.context
        let parent = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingProgram>()).first { $0.id == ids.parent })
        try ProgramLibrary.detachAndDelete(parent, context: context)
        let day = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingPlan>()).first { $0.id == ids.day })
        context.delete(day); try context.save()
    }
    func testDeletingSourceProgramAndDayDoesNotDeleteHistoricalSnapshot() throws {
        let url = try location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let ids = try writeHistory(url); try deleteSource(url, ids: ids)
        let reopened = try open(url)
        let record = try XCTUnwrap(reopened.context.fetch(FetchDescriptor<TrainingRecord>()).first)
        XCTAssertEqual(record.id, ids.record)
        XCTAssertEqual(try record.exercises().first?.name, "卧推")
        XCTAssertEqual(try record.completed(), [2])
        XCTAssertEqual(record.workoutID, ids.workout)
    }
}
