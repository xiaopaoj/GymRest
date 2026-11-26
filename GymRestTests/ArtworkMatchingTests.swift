import XCTest
import UIKit
import SwiftData
@testable import GymRest

@MainActor final class ArtworkMatchingTests: XCTestCase {
    func testImportedNamesAndAliasesResolveWithoutChangingPrescription() throws {
        let catalog = try ExerciseCatalog.bundled()
        let exercise = ExerciseSpec(name: "卧推", sets: 5, restSeconds: 75)
        XCTAssertEqual(catalog.resolve(exercise)?.id, "barbell-bench")
        XCTAssertEqual(catalog.matching(name: " DUMBBELL  BENCH-PRESS ")?.id, "dumbbell-bench")
        XCTAssertEqual(catalog.matching(name: "杠铃卧推")?.id, "barbell-bench")
        XCTAssertEqual(catalog.resolve(ExerciseSpec(name: "自定义重命名", catalogID: "barbell-bench"))?.id, "barbell-bench")
        XCTAssertEqual(catalog.resolve(ExerciseSpec(name: "杠铃卧推", catalogID: "missing-id"))?.id, "barbell-bench")
        XCTAssertEqual(catalog.matching(name: "对握高位下拉")?.id, "neutral-pulldown")
        XCTAssertEqual(catalog.matching(name: "窄距对握高位下拉")?.id, "neutral-pulldown")
        XCTAssertEqual(catalog.matching(name: "Close-Grip Lat Pulldown")?.id, "neutral-pulldown")
        XCTAssertEqual(catalog.item("neutral-pulldown")?.media.approved, true)
        XCTAssertEqual(catalog.matching(name: "EZ-Bar Curl")?.name, "站姿 EZ 曲杆弯举")
        XCTAssertNil(exercise.catalogID); XCTAssertEqual(exercise.sets, 5); XCTAssertEqual(exercise.restSeconds, 75)
    }
    func testAmbiguousAndPartialNamesDoNotSelectAnArbitraryVariant() throws {
        let catalog = try ExerciseCatalog.bundled()
        XCTAssertNil(catalog.matching(name: "bench"))
        XCTAssertNil(catalog.matching(name: "  "))
        let encoded = try JSONEncoder().encode(catalog)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var exercises = try XCTUnwrap(object["exercises"] as? [[String: Any]])
        var duplicate = exercises[0]; duplicate["id"] = "ambiguous-test"
        exercises.append(duplicate); object["exercises"] = exercises
        let ambiguous = try ExerciseCatalog.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(ambiguous.matching(name: catalog.exercises[0].name))
    }
    func testAllImportedFrameFilesAreBundledAndReadable() throws {
        let catalog = try ExerciseCatalog.bundled()
        let illustrated = catalog.exercises.filter { !($0.media.frameAssets ?? []).isEmpty }
        XCTAssertEqual(illustrated.count, 280)
        var filenames: Set<String> = []
        for item in illustrated {
            let frames = try XCTUnwrap(item.media.frameAssets)
            XCTAssertTrue((1...3).contains(frames.count))
            for filename in frames {
                let url = try XCTUnwrap(TestMediaResources.assetURL(filename), filename)
                let image = try XCTUnwrap(UIImage(contentsOfFile: url.path), filename)
                if filename.hasPrefix("wg-") { XCTAssertEqual(image.size.width, 512); XCTAssertEqual(image.size.height, 512) }
                else { XCTAssertGreaterThan(image.size.width, 0); XCTAssertGreaterThan(image.size.height, 0) }
                filenames.insert(filename)
            }
        }
        XCTAssertEqual(filenames.count, 775)
        let closeGrip = try XCTUnwrap(catalog.item("guide-close-grip-bench-press"))
        XCTAssertEqual(closeGrip.media.frameAssets, ["wg-close-grip-bench-press-1.png", "wg-close-grip-bench-press-3.png"])
        XCTAssertNotNil(Bundle.main.url(forResource: "WorkoutGuideSources", withExtension: "json"))
        XCTAssertNotNil(Bundle.main.url(forResource: "WorkoutGuide-LICENSE-ASSETS", withExtension: "txt"))
    }
    func testSupplementaryArtIsAvailableAndUnverifiedVariantsStayHidden() throws {
        let catalog = try ExerciseCatalog.bundled()
        for id in ["barbell-curl", "dumbbell-lunge", "dumbbell-calf"] {
            let item = try XCTUnwrap(catalog.item(id))
            XCTAssertTrue(item.media.approved); XCTAssertEqual(item.media.frameAssets?.count, 2)
            XCTAssertEqual(item.media.allowsPlayback, false)
        }
        let plank = try XCTUnwrap(catalog.matching(name: "Plank"))
        XCTAssertNil(plank.repetitions); XCTAssertNil(plank.spec().prescription?.repetitions)
        XCTAssertEqual(plank.supportsOrderAdvice, false)
        let custom = ExerciseSpec(name: "自定义")
        XCTAssertEqual(TrainingOrderAdvice.suggest([plank.spec(), custom], catalog: catalog, priority: .chest).map(\.exercise.name), [plank.name, custom.name])
    }
    private func namingStore() throws -> TrainingStore {
        try TrainingStore(container: ModelContainer(for: TrainingProgram.self, TrainingPlan.self, LibraryPreferences.self, ActiveTraining.self, TrainingRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }
    func testReviewedNamesAreUsedForNewPlansImportsAndNewSessions() throws {
        let alternative = ExerciseAlternative(name: "EZ-Bar Curl", catalogID: "guide-ez-bar-curl")
        let original = ExerciseSpec(name: "对握高位下拉", alternatives: [alternative])
        let plan = try TrainingPlan(name: "命名", position: 0, exercises: [original])
        XCTAssertEqual(try plan.exercises().first?.name, "窄距对握高位下拉")
        XCTAssertEqual(try plan.exercises().first?.alternatives.first?.name, "站姿 EZ 曲杆弯举")
        let archive = PlanArchive(plans: [.init(id: UUID(), name: "导入", exercises: [original])])
        let decoded = try PlanArchive.decode(JSONEncoder().encode(archive))
        XCTAssertEqual(decoded.plans.first?.exercises.first?.name, "窄距对握高位下拉")
        let session = try TrainingSession(planID: plan.id, planName: plan.name, exercises: [original], fallback: false)
        XCTAssertEqual(session.current.name, "窄距对握高位下拉")
        XCTAssertEqual(session.current.id, original.id)
        for name in ["杠铃弯举", "哑铃箭步蹲", "坐姿哑铃提踵", "我的自定义下拉"] {
            XCTAssertEqual(ExerciseNames.canonical(name, catalogID: nil), name)
        }
    }
    func testStoredNameUpdatesRollBackAndLeaveActiveAndHistorySnapshotsIntact() throws {
        let store = try namingStore(); let context = store.context
        let old = ExerciseSpec(name: "对握高位下拉", sets: 2, restSeconds: 75, prescription: SetValues(weight: 25))
        let plan = try TrainingPlan(name: "旧计划", position: 0)
        plan.exerciseData = try JSONEncoder().encode([old]); context.insert(plan)
        let originalData = plan.exerciseData
        var snapshot = try TrainingSession(planID: plan.id, planName: plan.name, exercises: [old], fallback: false)
        snapshot.exercises = [old]; snapshot.originalExercises = [old]
        let payload = try JSONEncoder().encode(snapshot)
        let active = ActiveTraining(payload: payload); context.insert(active)
        let record = try TrainingRecord(session: snapshot, end: Date()); context.insert(record)
        let historyData = record.exerciseData
        try context.save()
        XCTAssertThrowsError(try TrainingStore.standardizeStoredExerciseNames(in: context, beforeCommit: { throw TimerFailure.denied }))
        XCTAssertEqual(plan.exerciseData, originalData); XCTAssertFalse(context.hasChanges)
        try TrainingStore.standardizeStoredExerciseNames(in: context)
        var expected = old; expected.name = "窄距对握高位下拉"
        XCTAssertEqual(try plan.exercises(), [expected])
        XCTAssertEqual(active.payload, payload); XCTAssertEqual(record.exerciseData, historyData)
        try TrainingStore.standardizeStoredExerciseNames(in: context)
        XCTAssertFalse(context.hasChanges)
    }
    func testOldCustomNameProfileStillPrefillsWeightWithoutRewritingHistory() throws {
        let store = try namingStore()
        let old = ExerciseSpec(name: "对握高位下拉", sets: 1)
        let actual = SetValues(weight: 30, repetitions: 10)
        let parts = ["custom:对握高位下拉", actual.kind.rawValue, actual.unit.rawValue, actual.equipmentNote]
        let legacyKey = try JSONEncoder().encode(parts).base64EncodedString()
        var session = try TrainingSession(planID: UUID(), planName: "旧记录", exercises: [old], fallback: false)
        session.completed = [1]; session.phase = .completed
        session.performances = [[SetPerformance(exerciseName: old.name, catalogID: nil, values: actual, profileKey: legacyKey, completedAt: Date())]]
        let record = try TrainingRecord(session: session, end: Date())
        store.context.insert(record); try store.context.save()
        let revised = ExerciseSpec(name: "窄距对握高位下拉", sets: 1)
        XCTAssertEqual(try store.suggestedValues(for: revised).weight, 30)
        XCTAssertEqual(try record.performances()?.first?.first?.profileKey, legacyKey)
    }

}
