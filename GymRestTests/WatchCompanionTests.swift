import XCTest
import SwiftData
@testable import GymRest

@MainActor final class WatchCompanionTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)
    private func status(training: UUID = UUID(), run: UUID = UUID(), sequence: Int = 1, phase: WatchWorkoutStatus.Phase = .running,
                        at: Date? = nil, workout: UUID? = nil, token: UUID? = UUID()) -> WatchWorkoutStatus {
        WatchWorkoutStatus(trainingID: training, runID: run, sequence: sequence, phase: phase, sentAt: at ?? date,
            start: date.addingTimeInterval(-120), end: phase == .saved ? date : nil, workoutID: workout, heartRate: 90, activeEnergy: 10, issue: nil, controlToken: token)
    }
    private func snapshot(phase: String = "training", sequence: Int = 1) -> PhoneTrainingSnapshot {
        PhoneTrainingSnapshot(trainingID: UUID(), interactionID: UUID(), sequence: sequence, sentAt: date, plan: "训练", exercise: "侧平板支撑",
            currentSet: 0, sets: 3, completedSets: 0, totalSets: 3, phase: phase, part: "第1侧", completionTitle: "完成第1侧 · 换侧",
            values: "40秒/侧", durationSeconds: 40, effortStatus: nil, effortRegistered: false, effortEnd: nil, restEnd: nil, remaining: 40, reminderRegistered: false)
    }
    private func store() throws -> TrainingStore {
        try TrainingStore(container: ModelContainer(for: TrainingProgram.self, TrainingPlan.self, LibraryPreferences.self, ActiveTraining.self, TrainingRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }
    private func record(id: UUID) throws -> TrainingRecord {
        TrainingRecord(id: id, planName: "训练", startedAt: date.addingTimeInterval(-120), endedAt: date, finished: true,
            exerciseData: try JSONEncoder().encode([ExerciseSpec(name: "平板", sets: 1)]), completedData: try JSONEncoder().encode([1]))
    }
    func testPacketRoundTripPreservesTrainingAndWorkoutIdentity() throws {
        let training = snapshot(), workout = status(training: training.trainingID)
        let decoded = try CompanionPacket.decode(CompanionPacket(training: training, workout: workout).encoded())
        XCTAssertEqual(decoded.training, training); XCTAssertEqual(decoded.workout, workout)
        XCTAssertEqual(decoded.workout?.trainingID, decoded.training?.trainingID)
    }
    func testPacketRejectsUnknownVersionOversizeAndMalformedPayload() throws {
        XCTAssertThrowsError(try CompanionPacket(version: 2).encoded())
        XCTAssertThrowsError(try CompanionPacket.decode(Data(repeating: 0, count: 48 * 1024 + 1)))
        XCTAssertThrowsError(try CompanionPacket.decode(Data("{}".utf8)))
        XCTAssertThrowsError(try CompanionPacket(issue: String(repeating: "x", count: 301)).encoded())
    }
    func testStartRequestExpiresAndCannotHaveArbitraryLifetime() throws {
        let request = WatchStartRequest(id: UUID(), trainingID: UUID(), createdAt: date, expiresAt: date.addingTimeInterval(120), title: "训练")
        try request.validate()
        XCTAssertTrue(request.isFresh(at: date)); XCTAssertFalse(request.isFresh(at: date.addingTimeInterval(121)))
        let invalid = WatchStartRequest(id: UUID(), trainingID: UUID(), createdAt: date, expiresAt: date.addingTimeInterval(3600), title: "训练")
        XCTAssertThrowsError(try invalid.validate())
    }
    func testNoConnectionDoesNotMeanWorkoutHasEnded() throws {
        let running = status()
        try running.validate()
        XCTAssertTrue(running.isFresh(at: date))
        XCTAssertFalse(running.isFresh(at: date.addingTimeInterval(46)))
        XCTAssertEqual(running.phase, .running); XCTAssertFalse(running.phase.terminal)
    }
    func testSequenceRejectsDuplicateAndOutOfOrderStatuses() {
        let old = status(sequence: 5)
        XCTAssertFalse(status(training: old.trainingID, run: old.runID, sequence: 5).supersedes(old))
        XCTAssertFalse(status(training: old.trainingID, run: old.runID, sequence: 4).supersedes(old))
        XCTAssertTrue(status(training: old.trainingID, run: old.runID, sequence: 6, phase: .paused).supersedes(old))
    }
    func testFinalReceiptCannotRevertToRunning() {
        let old = status(sequence: 5, phase: .saved, workout: UUID())
        XCTAssertFalse(status(training: old.trainingID, run: old.runID, sequence: 6).supersedes(old))
        XCTAssertTrue(status(training: old.trainingID, run: old.runID, sequence: 6, phase: .saved, workout: old.workoutID).supersedes(old))
    }
    func testOldDifferentRunDoesNotReplaceCurrentRecording() {
        let running = status(at: date)
        XCTAssertFalse(status(sequence: 20, phase: .saved, at: date.addingTimeInterval(-10), workout: UUID()).supersedes(running))
        let saved = status(phase: .saved, workout: UUID())
        XCTAssertTrue(status(at: date.addingTimeInterval(1)).supersedes(saved))
    }
    func testDelayedPauseAfterResumeCannotReplayControlToken() throws {
        let initial = status()
        let pause = WatchCommand(kind: .pauseRecording, trainingID: initial.trainingID, runID: initial.runID, sentAt: date, controlToken: initial.controlToken)
        try pause.validate(); XCTAssertTrue(pause.targets(initial, at: date))
        let resumed = status(training: initial.trainingID, run: initial.runID, sequence: 5, token: UUID())
        XCTAssertFalse(pause.targets(resumed, at: date.addingTimeInterval(5)))
        XCTAssertFalse(pause.targets(initial, at: date.addingTimeInterval(31)))
    }
    func testQueuedSaveTargetsOnlyOneExactRunAndTraining() throws {
        let running = status()
        let save = WatchCommand(kind: .saveRecording, trainingID: running.trainingID, runID: running.runID, sentAt: date, requestedEnd: date)
        try save.validate()
        XCTAssertTrue(save.targets(running, at: date.addingTimeInterval(3600)))
        XCTAssertFalse(save.targets(status(training: running.trainingID), at: date.addingTimeInterval(3600)))
        XCTAssertFalse(save.targets(status(run: running.runID), at: date))
    }
    func testTrainingActionMustCarryKnownActionAndInteractionToken() throws {
        XCTAssertThrowsError(try WatchCommand(kind: .trainingAction, trainingID: UUID(), action: "completeSet", sentAt: date).validate())
        XCTAssertThrowsError(try WatchCommand(kind: .trainingAction, trainingID: UUID(), interactionID: UUID(), action: "deleteAll", sentAt: date).validate())
        try WatchCommand(kind: .trainingAction, trainingID: UUID(), interactionID: UUID(), action: "startEffort", sentAt: date).validate()
    }
    func testSavedReceiptRequiresActualHealthIdentifierAndDates() throws {
        XCTAssertThrowsError(try status(phase: .saved).validate())
        try status(phase: .saved, workout: UUID()).validate()
    }
    func testSnapshotCarriesHalfSetWithoutClaimingWholeSet() throws {
        let value = snapshot()
        try value.validate(); XCTAssertEqual(value.currentSet, 0); XCTAssertEqual(value.completedSets, 0)
        XCTAssertEqual(value.part, "第1侧"); XCTAssertEqual(value.durationSeconds, 40)
        XCTAssertFalse(value.isFresh(at: date.addingTimeInterval(60)))
    }
    func testReceiptLinksByIdentityRatherThanTimeAndIsIdempotent() throws {
        let store = try store(), target = try record(id: UUID()), other = try record(id: UUID())
        store.context.insert(target); store.context.insert(other); try store.context.save()
        let receipt = status(training: target.id, phase: .saved, workout: UUID())
        XCTAssertTrue(try store.attachWatchReceipt(receipt)); XCTAssertTrue(try store.attachWatchReceipt(receipt))
        XCTAssertEqual(target.workoutID, receipt.workoutID?.uuidString); XCTAssertEqual(target.workoutSource, "GymRest Watch")
        XCTAssertNil(other.workoutID)
        XCTAssertEqual(try store.context.fetch(FetchDescriptor<TrainingRecord>()).count, 2)
    }
    func testReceiptBeforePhoneArchiveWaitsWithoutInventingARecord() throws {
        let store = try store()
        XCTAssertFalse(try store.attachWatchReceipt(status(phase: .saved, workout: UUID())))
        XCTAssertTrue(try store.context.fetch(FetchDescriptor<TrainingRecord>()).isEmpty)
    }
    func testReceiptPreservesExistingManualHealthAssociation() throws {
        let store = try store(), target = try record(id: UUID()), oldID = UUID().uuidString
        target.workoutID = oldID; target.workoutSource = "用户已选记录"
        store.context.insert(target); try store.context.save()
        XCTAssertThrowsError(try store.attachWatchReceipt(status(training: target.id, phase: .saved, workout: UUID())))
        XCTAssertEqual(target.workoutID, oldID); XCTAssertEqual(target.workoutSource, "用户已选记录")
    }
    func testUnlinkingIsNotUndoneByReplayedReceiptAndBackupKeepsAcknowledgement() throws {
        let store = try store(), target = try record(id: UUID())
        store.context.insert(target); try store.context.save()
        let receipt = status(training: target.id, phase: .saved, workout: UUID())
        XCTAssertTrue(try store.attachWatchReceipt(receipt))
        target.workoutID = nil; target.workoutSource = nil; try store.context.save()
        XCTAssertTrue(try store.attachWatchReceipt(receipt)); XCTAssertNil(target.workoutID)
        let backup = try LibraryBackup.capture(store.context, preferences: store.preferences)
        let decoded = try LibraryBackup.decode(backup.encoded())
        XCTAssertEqual(decoded.records[0].watchWorkoutReceiptID, receipt.workoutID?.uuidString)
    }
}
