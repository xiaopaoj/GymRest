import Foundation
import SwiftData

@MainActor enum PlanEditing {
    static func save(_ exercises: [ExerciseSpec], to plan: TrainingPlan, context: ModelContext,
                     beforeCommit: () throws -> Void = {}) throws {
        // Keep validation and durable saving on the same path for add/edit/delete/reorder.
        for exercise in exercises { try exercise.validate() }
        do {
            try plan.setExercises(exercises)
            try beforeCommit()
            try context.save()
        } catch { context.rollback(); throw error }
    }
}
