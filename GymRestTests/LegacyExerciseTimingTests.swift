import XCTest
import SwiftData
@testable import GymRest

@MainActor final class LegacyExerciseTimingTests: XCTestCase {
    private func store() throws -> TrainingStore {
        try TrainingStore(container: ModelContainer(for: TrainingProgram.self, TrainingPlan.self, LibraryPreferences.self,
            ActiveTraining.self, TrainingRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }
    func testLegacySecondsAndEverySideSecondsBecomeEffortTimers() throws {
        for note in ["按秒计：60秒/组", "每组60秒", "60秒/组"] {
            let values = ExerciseTiming.resolve(SetValues(repetitions: 60, equipmentNote: note))
            XCTAssertEqual(values.durationSeconds, 60); XCTAssertNil(values.repetitions)
            try values.validate()
        }
        let side = ExerciseTiming.resolve(SetValues(repetitions: 40, equipmentNote: "每侧40秒"))
        XCTAssertEqual(side.durationSeconds, 40); XCTAssertEqual(side.sideCount, 2)
    }
    func testRestCountsAmbiguityAndExplicitDurationRemainUntouched() {
        for note in ["组间休息60秒", "每侧12次", "按秒计：30-60秒/组", "按秒计：40秒或每组60秒",
                     "每组60秒内完成60次", "每组60秒，另做30秒", "每组60秒，做12次",
                     "每组60秒；30秒", "每组60秒/侧", "每组60seconds"] {
            let value = SetValues(repetitions: 60, equipmentNote: note)
            XCTAssertEqual(ExerciseTiming.resolve(value), value)
        }
        let explicit = SetValues(equipmentNote: "按秒计：60秒/组", durationSeconds: 45)
        XCTAssertEqual(ExerciseTiming.resolve(explicit), explicit)
        let conflict = SetValues(repetitions: 12, equipmentNote: "每侧40秒")
        XCTAssertEqual(ExerciseTiming.resolve(conflict), conflict)
    }
    func testImportedV3MainAndAlternativeUpgradeAndExportAsV4() throws {
        let old = ExerciseSpec(name: "平板支撑", catalogID: "plank", prescription: SetValues(repetitions: 60, equipmentNote: "按秒计：60秒/组"))
        var day = ExerciseSpec(name: "死虫式", alternatives: [ExerciseAlternative(name: "侧平板支撑", prescription: SetValues(repetitions: 40, equipmentNote: "每侧40秒"))])
        day.alternatives.append(ExerciseAlternative(name: "计数动作", prescription: SetValues(repetitions: 12)))
        let archive = PlanArchive(version: 3, plans: [.init(id: UUID(), name: "旧计划", exercises: [old, day])])
        let decoded = try PlanArchive.decode(JSONEncoder().encode(archive))
        XCTAssertEqual(decoded.plans[0].exercises[0].prescription?.durationSeconds, 60)
        XCTAssertEqual(decoded.plans[0].exercises[1].alternatives[0].prescription?.sideCount, 2)
        XCTAssertNil(decoded.plans[0].exercises[1].alternatives[1].prescription?.durationSeconds)
        XCTAssertEqual(decoded.plans[0].exercises[0].id, old.id)
        let exportedDay = try TrainingPlan(name: "已升级", position: 0, exercises: decoded.plans[0].exercises)
        let exported = try PlanArchive.decode(PlanArchive.export(plans: [exportedDay]))
        XCTAssertEqual(exported.version, 4)
    }
    func testSavedPlanCleanupPreservesActiveAndFinishedSnapshots() throws {
        let store = try store()
        let old = ExerciseSpec(name: "平板支撑", prescription: SetValues(repetitions: 60, equipmentNote: "按秒计：60秒/组"))
        let plan = try TrainingPlan(name: "旧计划", position: 0)
        plan.exerciseData = try JSONEncoder().encode([old]); store.context.insert(plan)
        var snapshot = try TrainingSession(planID: plan.id, planName: plan.name, exercises: [old], fallback: false)
        snapshot.setDrafts = [old.prescription!]
        let payload = try JSONEncoder().encode(snapshot)
        let active = ActiveTraining(payload: payload); store.context.insert(active)
        let record = try TrainingRecord(session: snapshot, end: Date()); store.context.insert(record)
        let history = record.exerciseData
        try store.context.save()
        try TrainingStore.standardizeStoredExerciseNames(in: store.context)
        XCTAssertEqual(try plan.exercises()[0].prescription?.durationSeconds, 60)
        XCTAssertEqual(active.payload, payload); XCTAssertEqual(record.exerciseData, history)
        XCTAssertEqual(snapshot.currentSetValues.durationSeconds, 60)
    }
    func testLegacyPlankStartsRealTimerAndCannotCompleteEarly() async throws {
        let store = try store(); let timer = MockTimerService()
        let controller = try TrainingController(store: store, alarm: timer, notification: timer)
        let plan = try TrainingPlan(name: "旧计划", position: 0, exercises: [ExerciseSpec(name: "平板支撑",
            prescription: SetValues(repetitions: 60, equipmentNote: "按秒计：60秒/组"))])
        await controller.start(plan: plan); await controller.startEffort()
        XCTAssertNil(controller.error)
        XCTAssertEqual(controller.session?.effortTimer?.remaining, 60)
        XCTAssertEqual(timer.lastContext?.kind, "effort")
        await controller.completeSet()
        XCTAssertNotNil(controller.error); XCTAssertEqual(controller.session?.completedSets, 0)
    }
    func testNameOnlyTimedDefaultDoesNotChangeLegacyLoadKindOrCountedVariants() throws {
        let store = try store()
        let values = try store.suggestedValues(for: ExerciseSpec(name: "平板支撑"))
        XCTAssertEqual(values.durationSeconds, 40); XCTAssertEqual(values.kind, .total)
        let counted = SetValues(repetitions: 12)
        XCTAssertEqual(try store.suggestedValues(for: ExerciseSpec(name: "平板支撑", prescription: counted)), counted)
        XCTAssertNil(try store.suggestedValues(for: ExerciseSpec(name: "平板支撑交替触肩")).durationSeconds)
    }
    func testSwitchingBackToCountedCanRemoveOnlyLegacyTimingHint() {
        XCTAssertEqual(ExerciseTiming.removingLegacyHint(from: "健身房A；按秒计：60秒/组"), "健身房A")
        XCTAssertEqual(ExerciseTiming.removingLegacyHint(from: "每侧40秒"), "")
        XCTAssertEqual(ExerciseTiming.removingLegacyHint(from: "每组60秒内完成60次"), "每组60秒内完成60次")
        XCTAssertEqual(ExerciseTiming.removingLegacyHint(from: "器械A，组间休息60秒"), "器械A，组间休息60秒")
    }
}
