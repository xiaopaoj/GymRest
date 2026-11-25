import Foundation
import SwiftData

@MainActor enum PlanEditing {
    static func save(_ exercises: [ExerciseSpec], to plan: TrainingPlan, context: ModelContext,
                     beforeCommit: () throws -> Void = {}) throws {
        // Keep validation and durable saving on the same path for add/edit/delete/reorder.
        for exercise in exercises { try exercise.validate() }
        let originalData = plan.exerciseData
        do {
            try plan.setExercises(exercises)
            context.processPendingChanges()
            try beforeCommit()
            try context.save()
        } catch {
            context.discardPendingChanges()
            // Keep the existing observed object in sync even if SwiftData retains a stale property value.
            if plan.exerciseData != originalData {
                plan.exerciseData = originalData
                context.discardPendingChanges()
            }
            throw error
        }
    }
}
