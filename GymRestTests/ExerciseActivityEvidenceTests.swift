import XCTest
@testable import GymRest

final class ExerciseActivityEvidenceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private func sample(age: TimeInterval = 30, product: String? = "Watch9,1", minutes: Double = 1, span: TimeInterval = 60, manual: Bool = false) -> ExerciseActivitySample {
        let end = now.addingTimeInterval(-age)
        return ExerciseActivitySample(id: UUID(), start: end.addingTimeInterval(-span), end: end,
            minutes: minutes, productType: product, userEntered: manual)
    }
    func testRecentWatchSamplesAreOnlyActivityEvidence() {
        let evidence = ExerciseActivityEvidence.analyze([sample()], at: now)
        XCTAssertEqual(evidence.kind, .recentActivity)
        XCTAssertTrue(evidence.title.contains("未确认"))
    }
    func testOldAndExpiredSamplesDoNotSuggestCurrentActivity() {
        XCTAssertEqual(ExerciseActivityEvidence.analyze([sample(age: 181)], at: now).kind, .olderActivity)
        XCTAssertEqual(ExerciseActivityEvidence.analyze([sample(age: 901)], at: now).kind, .noData)
    }
    func testEmptyDataNeverMeansWorkoutIsOff() {
        let evidence = ExerciseActivityEvidence.analyze([], at: now)
        XCTAssertEqual(evidence.kind, .noData)
        XCTAssertTrue(evidence.title.contains("无法判断"))
        XCTAssertNil(evidence.latestSampleEnd)
    }
    func testUnknownOrPhoneSourceIsNotClaimedAsWatch() {
        for product: String? in [nil, "iPhone17,1", ""] {
            XCTAssertEqual(ExerciseActivityEvidence.analyze([sample(product: product)], at: now).kind, .unknownSource)
        }
    }
    func testManualFutureInvalidAndLongAggregatesAreIgnored() {
        for value in [sample(manual: true), sample(age: -1), sample(minutes: .nan), sample(minutes: -1),
                      sample(minutes: 0), sample(minutes: 2), sample(span: 0), sample(span: 3600)] {
            XCTAssertEqual(ExerciseActivityEvidence.analyze([value], at: now).kind, .noData)
        }
    }
    func testEvidenceAgesWithoutNewQueryAndOldWatchIsNotOverriddenByPhone() {
        let samples = [sample(age: 200), sample(age: 0, product: "iPhone17,1")]
        XCTAssertEqual(ExerciseActivityEvidence.analyze(samples, at: now).kind, .olderActivity)
        let recent = sample()
        XCTAssertEqual(ExerciseActivityEvidence.analyze([recent], at: now.addingTimeInterval(300)).kind, .olderActivity)
    }
}

@MainActor final class HealthActivityMonitorTests: XCTestCase {
    private enum Failure: Error { case denied, query }
    private func defaults() -> UserDefaults {
        let name = "HealthActivityMonitorTests." + UUID().uuidString
        let value = UserDefaults(suiteName: name)!
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return value
    }
    func testNoQueryBeforeExplicitRequestAndPollingDoesNotReauthorize() async {
        var authorizationCalls = 0, queries = 0
        let monitor = HealthActivityMonitor(defaults: defaults(), authorize: { authorizationCalls += 1 }, fetch: { _ in queries += 1; return [] })
        await monitor.refresh()
        XCTAssertEqual(queries, 0)
        await monitor.requestAccess()
        await monitor.refresh()
        XCTAssertEqual(authorizationCalls, 1)
        XCTAssertEqual(queries, 2)
        XCTAssertTrue(monitor.authorizationRequested)
        XCTAssertEqual(monitor.evidence(at: .now).kind, .noData)
    }
    func testFailedAuthorizationDoesNotStartPolling() async {
        var queries = 0
        let monitor = HealthActivityMonitor(defaults: defaults(), authorize: { throw Failure.denied }, fetch: { _ in queries += 1; return [] })
        await monitor.requestAccess(); await monitor.refresh()
        XCTAssertEqual(queries, 0)
        XCTAssertFalse(monitor.authorizationRequested)
        XCTAssertNotNil(monitor.issue)
        XCTAssertFalse(monitor.busy)
    }
    func testQueryErrorClearsPreviousEvidence() async {
        var fail = false
        let now = Date()
        let sample = ExerciseActivitySample(id: UUID(), start: now.addingTimeInterval(-60), end: now, minutes: 1, productType: "Watch9,1")
        let monitor = HealthActivityMonitor(defaults: defaults(), authorize: {}, fetch: { _ in
            if fail { throw Failure.query }; return [sample]
        })
        await monitor.requestAccess()
        XCTAssertEqual(monitor.evidence(at: now).kind, .recentActivity)
        fail = true; await monitor.refresh()
        XCTAssertEqual(monitor.evidence(at: now).kind, .noData)
        XCTAssertNotNil(monitor.issue)
    }
}
