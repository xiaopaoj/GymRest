import XCTest
import SwiftData
@testable import GymRest

@MainActor final class RecoveryProtectionTests: XCTestCase {
    private func fixture() throws -> (TrainingStore, ActiveTraining, MockTimerService) {
        let container = try ModelContainer(for: TrainingProgram.self, TrainingPlan.self, LibraryPreferences.self, ActiveTraining.self, TrainingRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = try TrainingStore(container: container)
        let invalid = ActiveTraining(payload: Data("invalid state".utf8))
        store.context.insert(invalid); try store.context.save()
        return (store, invalid, MockTimerService())
    }
    func testInvalidActiveProgressDoesNotPreventAccessToLibrary() throws {
        let (store, invalid, timer) = try fixture()
        let controller = try TrainingController(store: store, alarm: timer, notification: timer)
        XCTAssertNotNil(controller.recoveryIssue)
        XCTAssertNotNil(controller.error)
        XCTAssertNil(controller.session)
        XCTAssertEqual(try store.context.fetch(FetchDescriptor<TrainingPlan>()).count, 5)
        XCTAssertEqual(invalid.payload, Data("invalid state".utf8))
    }
    func testStartAndEndCannotOverwriteUnreadableProgress() async throws {
        let (store, invalid, timer) = try fixture()
        let controller = try TrainingController(store: store, alarm: timer, notification: timer)
        let day = try TrainingPlan(name: "周一", position: 0, exercises: [ExerciseSpec(name: "卧推")])
        await controller.start(plan: day); await controller.end()
        XCTAssertNil(controller.session)
        XCTAssertNotNil(controller.recoveryIssue)
        XCTAssertEqual(invalid.payload, Data("invalid state".utf8))
        XCTAssertEqual(try store.context.fetch(FetchDescriptor<ActiveTraining>()).count, 1)
        XCTAssertEqual(timer.starts, 0)
    }
    func testRetryFailurePreservesDataAndSuccessfulReloadClearsBlock() async throws {
        let (store, invalid, timer) = try fixture()
        let controller = try TrainingController(store: store, alarm: timer, notification: timer)
        await controller.retryRecovery()
        XCTAssertNotNil(controller.recoveryIssue)
        let valid = try TrainingSession(planID: UUID(), planName: "恢复训练", exercises: [ExerciseSpec(name: "卧推")], fallback: false)
        invalid.payload = try JSONEncoder().encode(valid); try store.context.save()
        await controller.retryRecovery()
        XCTAssertNil(controller.recoveryIssue)
        XCTAssertNil(controller.error)
        XCTAssertEqual(controller.session, valid)
        XCTAssertEqual(timer.starts, 0)
    }
}
