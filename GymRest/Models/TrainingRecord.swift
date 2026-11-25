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
    var workoutID: String?
    var workoutSource: String?
    var workoutStart: Date?
    var workoutEnd: Date?

    init(session: TrainingSession, end: Date) throws {
        id = session.sessionID ?? session.planID; planName = session.planName
        startedAt = session.startedAt; endedAt = end; finished = session.phase == .completed
        exerciseData = try JSONEncoder().encode(session.exercises)
        completedData = try JSONEncoder().encode(session.completed)
        performedNamesData = try session.performedNames.map { try JSONEncoder().encode($0) }
    }
    func exercises() throws -> [ExerciseSpec] { try JSONDecoder().decode([ExerciseSpec].self, from: exerciseData) }
    func completed() throws -> [Int] { try JSONDecoder().decode([Int].self, from: completedData) }
}
