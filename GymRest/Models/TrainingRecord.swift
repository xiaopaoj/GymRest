import Foundation
import SwiftData

@Model final class TrainingRecord {
    @Attribute(.unique) var id: UUID
    var planName: String
    var startedAt: Date?
    var endedAt: Date
    var finished: Bool
    var exerciseData: Data
    var completedData: Data
    var performedNamesData: Data?
    var performancesData: Data?
    var workoutID: String?
    // Legacy receipt marker retained for existing SwiftData stores and backups.
    var watchWorkoutReceiptID: String?
    var workoutSource: String?
    var workoutStart: Date?
    var workoutEnd: Date?

    init(id: UUID, planName: String, startedAt: Date?, endedAt: Date, finished: Bool, exerciseData: Data, completedData: Data) {
        self.id = id; self.planName = planName; self.startedAt = startedAt; self.endedAt = endedAt; self.finished = finished
        self.exerciseData = exerciseData; self.completedData = completedData
    }
    init(session: TrainingSession, end: Date) throws {
        id = session.sessionID ?? session.planID; planName = session.planName
        startedAt = session.startedAt; endedAt = end; finished = session.phase == .completed
        exerciseData = try JSONEncoder().encode(session.exercises)
        completedData = try JSONEncoder().encode(session.completed)
        performedNamesData = try session.performedNames.map { try JSONEncoder().encode($0) }
        performancesData = try session.performances.map { try JSONEncoder().encode($0) }
    }
    func performances() throws -> [[SetPerformance]]? {
        guard let performancesData else { return nil }
        let values = try JSONDecoder().decode([[SetPerformance]].self, from: performancesData)
        let counts = try completed()
        guard values.count == counts.count, zip(values, counts).allSatisfy({ $0.0.count == $0.1 }) else { throw TrainingError.invalidSession }
        for exercise in values { for set in exercise { try set.validate() } }
        return values
    }
    func exercises() throws -> [ExerciseSpec] { try JSONDecoder().decode([ExerciseSpec].self, from: exerciseData) }
    func completed() throws -> [Int] { try JSONDecoder().decode([Int].self, from: completedData) }
}
