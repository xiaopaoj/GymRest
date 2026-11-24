import XCTest
@testable import GymRest

@MainActor
final class ProbeTests: XCTestCase {
    private func makeModel() -> (ProbeModel, MockTimerService, UserDefaults) {
        let store = UserDefaults(suiteName: UUID().uuidString)!
        let mock = MockTimerService()
        return (ProbeModel(alarm: mock, notification: MockTimerService(), defaults: store), mock, store)
    }
    func testReplacementAndCancellation() async {
        let (model, mock, _) = makeModel()
        await model.start(seconds: 30)
        let first = model.task!.id
        await model.start(seconds: 60)
        XCTAssertFalse(mock.ids.contains(first))
        XCTAssertEqual(mock.ids.count, 1)
        await model.cancel()
        XCTAssertTrue(mock.ids.isEmpty)
        XCTAssertNil(model.task)
    }
    func testInvalidDurationsNeverSchedule() async {
        let (model, mock, _) = makeModel()
        for seconds in [-1, 0, 86401] { await model.start(seconds: seconds) }
        XCTAssertEqual(mock.starts, 0)
        XCTAssertNotNil(model.error)
    }
    func testRestoresPersistedIdentifier() async {
        let (model, mock, store) = makeModel()
        await model.start(seconds: 30)
        let restored = ProbeModel(alarm: mock, notification: MockTimerService(), defaults: store)
        XCTAssertEqual(restored.task, model.task)
        await restored.refresh()
        XCTAssertEqual(restored.systemStatus, "countdown")
    }
}
