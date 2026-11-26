import XCTest
import UIKit
import SwiftData
@testable import GymRest

@MainActor final class QualityAndDeviceFlowTests: XCTestCase {
    func testEveryBundledActionHasConcreteStepsAndMistakes() throws {
        let catalog = try ExerciseCatalog.bundled(); let guides = try ExerciseGuides.bundled()
        XCTAssertEqual(Set(guides.items.map(\.catalogID)), Set(catalog.exercises.map(\.id)))
        XCTAssertEqual(catalog.exercises.count, 306)
        for item in guides.items {
            XCTAssertGreaterThanOrEqual(item.steps.count, 4); XCTAssertGreaterThanOrEqual(item.mistakes.count, 3)
            XCTAssertTrue(item.setup.contains(item.name)); XCTAssertFalse(item.references.isEmpty)
        }
    }
    func testVisualReviewWithholdsMismatchesAndSelectsOnlySuitablePoses() throws {
        let catalog = try ExerciseCatalog.bundled()
        for id in ["guide-swimming", "guide-towel-hamstring-curl", "guide-dragon-flag", "cable-lateral"] {
            let item = try XCTUnwrap(catalog.item(id))
            XCTAssertFalse(item.media.approved); XCTAssertTrue(item.media.frameAssets?.isEmpty ?? true)
            XCTAssertNotNil(item.media.reviewNote)
        }
        XCTAssertEqual(catalog.item("guide-ab-wheel")?.media.frameAssets?.count, 1)
        XCTAssertEqual(catalog.item("guide-dead-bug")?.media.frameAssets?.count, 2)
        XCTAssertEqual(catalog.item("guide-cable-lateral-raise")?.name, "双臂绳索侧平举")
        XCTAssertEqual(catalog.item("cable-lateral")?.name, "单臂绳索侧平举")
        XCTAssertNil(catalog.matching(name: "绳索侧平举"))
        XCTAssertTrue(catalog.exercises.allSatisfy { $0.media.allowsPlayback != true })
    }
    func testAllOriginalImageAndReviewResourcesAreActuallyBundled() throws {
        struct Frame: Decodable { let file: String }
        struct Entry: Decodable { let frames: [Frame] }
        struct Source: Decodable { let exercises: [Entry] }
        var filenames: Set<String> = []
        for source in ["WorkoutGuideSources", "EverkineticSources"] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: source, withExtension: "json"))
            let document = try JSONDecoder().decode(Source.self, from: Data(contentsOf: url))
            for exercise in document.exercises {
                for frame in exercise.frames { filenames.insert(frame.file) }
            }
        }
        XCTAssertEqual(filenames.count, 912)
        for filename in filenames {
            let url = try XCTUnwrap(TestMediaResources.assetURL(filename), filename)
            XCTAssertNotNil(UIImage(contentsOfFile: url.path), filename)
        }
        XCTAssertNotNil(Bundle.main.url(forResource: "WorkoutGuideMediaReview", withExtension: "json"))
        XCTAssertNotNil(Bundle.main.url(forResource: "Everkinetic-LICENSE", withExtension: "txt"))
        XCTAssertTrue(try XCTUnwrap(ExerciseCatalog.bundled().item("dumbbell-calf")).media.reviewNote?.contains("单腿") == true)
    }
    func testHealthQueryRunsOnlyAfterExplicitCallAndUsesFifteenMinuteWindow() async throws {
        var authorizationCalls = 0; var fetched: DateInterval?
        let start = Date(timeIntervalSince1970: 1_800_000_000), end = Date(timeIntervalSince1970: 1_800_003_600)
        let runner = WorkoutQueryRunner(authorize: { authorizationCalls += 1 }, fetch: { interval in fetched = interval; return [] })
        XCTAssertEqual(authorizationCalls, 0); XCTAssertNil(fetched)
        let result = try await runner.candidates(start: start, end: end)
        XCTAssertTrue(result.isEmpty); XCTAssertEqual(authorizationCalls, 1)
        XCTAssertEqual(fetched?.start, start.addingTimeInterval(-900)); XCTAssertEqual(fetched?.end, end.addingTimeInterval(900))
    }
    func testAuthorizationErrorPreventsHealthQuery() async throws {
        var fetched = false
        let runner = WorkoutQueryRunner(authorize: { throw TimerFailure.denied }, fetch: { _ in fetched = true; return [] })
        do { _ = try await runner.candidates(start: Date(), end: Date().addingTimeInterval(60)); XCTFail("Expected authorization failure") }
        catch { XCTAssertFalse(fetched) }
    }
    func testInvalidTimeAndCancelledQueryCannotStartFetching() async throws {
        var calls = 0
        let runner = WorkoutQueryRunner(authorize: { calls += 1 }, fetch: { _ in calls += 1; return [] })
        do { _ = try await runner.candidates(start: Date(), end: Date().addingTimeInterval(-60)); XCTFail("Expected invalid interval") } catch {}
        XCTAssertEqual(calls, 0)
        let task = Task { () -> Bool in
            try? await Task.sleep(for: .milliseconds(10))
            do { _ = try await runner.candidates(start: Date(), end: Date().addingTimeInterval(60)); return false }
            catch { return true }
        }
        task.cancel()
        let cancelled = await task.value
        XCTAssertTrue(cancelled); XCTAssertEqual(calls, 0)
    }
    func testHealthCandidatesAreDeduplicatedRankedAndDoNotInventWatchSource() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000), end = start.addingTimeInterval(3600)
        let full = WorkoutCandidate(id: UUID(), start: start, end: end, title: "力量训练", source: "其他App", device: nil)
        let partial = WorkoutCandidate(id: UUID(), start: start, end: start.addingTimeInterval(300), title: "其他运动", source: "原始来源", device: "原始设备")
        let outside = WorkoutCandidate(id: UUID(), start: start.addingTimeInterval(-7200), end: start.addingTimeInterval(-3600), title: "过早", source: "来源", device: nil)
        let ranked = try WorkoutMatching.ranked([partial, full, full, outside], start: start, end: end)
        XCTAssertEqual(ranked.map(\.id), [full.id, partial.id])
        XCTAssertEqual(ranked[0].source, "其他App"); XCTAssertNil(ranked[0].device)
        let invalid = WorkoutCandidate(id: UUID(), start: end, end: start, title: "坏记录", source: "来源", device: nil)
        XCTAssertEqual(invalid.overlapScore(start: start, end: end), 0)
    }
    func testLockScreenStateDecodesOlderPayloadWithoutDiagnosticTimestamp() throws {
        let state = TrainingActivityAttributes.ContentState(interactionID: UUID().uuidString, planName: "训练", exerciseName: "卧推", phase: "training",
            completedSet: 1, totalSets: 3, nextStep: "继续", restEnd: nil, remaining: 0, reminderRegistered: false, issue: nil, blocked: false)
        let decoded = try JSONDecoder().decode(TrainingActivityAttributes.ContentState.self, from: JSONEncoder().encode(state))
        XCTAssertNil(decoded.synchronizedAt); XCTAssertEqual(decoded.completedSet, 1)
    }
}
