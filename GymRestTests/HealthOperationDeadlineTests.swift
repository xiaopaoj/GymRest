import XCTest
@testable import GymRest

@MainActor final class HealthOperationDeadlineTests: XCTestCase {
    private enum Failure: Error { case denied }
    func testSuccessAndErrorAreReturned() async throws {
        let value = try await HealthOperationDeadline.run(timeout: .seconds(1)) { 42 }
        XCTAssertEqual(value, 42)
        do {
            let _: Int = try await HealthOperationDeadline.run(timeout: .seconds(1)) { throw Failure.denied }
            XCTFail("Expected authorization failure")
        } catch { XCTAssertTrue(error is Failure) }
    }
    func testNonCooperativeOperationTimesOutAndLateReplyIsIgnored() async {
        var late: CheckedContinuation<Int, Never>?
        do {
            let _: Int = try await HealthOperationDeadline.run(timeout: .milliseconds(20)) {
                await withCheckedContinuation { late = $0 }
            }
            XCTFail("Expected timeout")
        } catch { XCTAssertTrue(error is HealthOperationTimeout) }
        late?.resume(returning: 42)
        await Task.yield()
    }
    func testCancelledRequestReturnsWithoutWaitingForHealthCallback() async {
        var late: CheckedContinuation<Int, Never>?
        let request = Task { @MainActor in
            try await HealthOperationDeadline.run(timeout: .seconds(1)) {
                await withCheckedContinuation { late = $0 }
            }
        }
        while late == nil { await Task.yield() }
        request.cancel()
        do { _ = try await request.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        late?.resume(returning: 42)
        await Task.yield()
    }
    func testMonitorReportsEmptyResultAndTimeoutInsteadOfStayingBusy() async {
        let name = "HealthOperationDeadlineTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var late: CheckedContinuation<[ExerciseActivitySample], Never>?
        var shouldHang = false
        let monitor = HealthActivityMonitor(defaults: defaults, authorize: {}, fetch: { _ in
            if shouldHang { return await withCheckedContinuation { late = $0 } }
            return []
        }, queryTimeout: .milliseconds(20))
        await monitor.requestAccess()
        XCTAssertEqual(monitor.phase, .finished)
        XCTAssertTrue(monitor.feedback.contains("未返回"))
        shouldHang = true; await monitor.refresh()
        XCTAssertEqual(monitor.phase, .failed)
        XCTAssertFalse(monitor.busy); XCTAssertNotNil(monitor.issue)
        late?.resume(returning: [])
        await Task.yield()
        XCTAssertEqual(monitor.phase, .failed)
    }
}
