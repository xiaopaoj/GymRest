import Foundation

enum TrainingPhase: String, Codable, Sendable { case idle, training, resting, paused, completed }

struct TrainingSession: Codable, Equatable, Sendable {
    var sessionID: UUID? = UUID()
    var startedAt: Date? = Date()
    let planID: UUID
    let planName: String
    var exercises: [ExerciseSpec]
    var originalExercises: [ExerciseSpec]?
    var performedNames: [[String]]?
    let fallback: Bool
    var index = 0
    var completed: [Int]
    var phase: TrainingPhase = .training
    var timerID: UUID?
    var restEnd: Date?
    var remaining: TimeInterval = 0
    var originalRest = 0
    // A failed registration must never masquerade as an active system reminder.
    var reminderRegistered = false

    init(planID: UUID, planName: String, exercises: [ExerciseSpec], fallback: Bool) throws {
        guard !exercises.isEmpty else { throw TrainingError.emptyPlan }
        for exercise in exercises { try exercise.validate() }
        self.planID = planID; self.planName = planName; self.exercises = exercises; self.fallback = fallback
        completed = Array(repeating: 0, count: exercises.count)
        originalExercises = exercises
        performedNames = Array(repeating: [], count: exercises.count)
    }
    func validate() throws {
        guard !exercises.isEmpty, exercises.indices.contains(index), completed.count == exercises.count,
              zip(completed, exercises).allSatisfy({ $0.0 >= 0 && $0.0 <= $0.1.sets }),
              remaining.isFinite, remaining >= 0, remaining <= 86400,
              phase == .training || phase == .resting || phase == .paused,
              phase != .resting || (timerID != nil && restEnd != nil) else { throw TrainingError.invalidSession }
        for exercise in exercises { try exercise.validate() }
        if let originalExercises {
            guard originalExercises.count == exercises.count else { throw TrainingError.invalidSession }
            for exercise in originalExercises { try exercise.validate() }
        }
        if let performedNames {
            guard performedNames.count == exercises.count,
                  zip(performedNames, completed).allSatisfy({ $0.0.count == $0.1 }) else { throw TrainingError.invalidSession }
        }
    }
    var current: ExerciseSpec { exercises[index] }
    var restContext: RestContext {
        let next: String
        if completed[index] < current.sets { next = "下一组：第 \(completed[index] + 1) / \(current.sets) 组" }
        else if index + 1 < exercises.count { next = "下一动作：" + exercises[index + 1].name }
        else { next = "本次训练即将完成" }
        return RestContext(planName: planName, exerciseName: current.name, completedSet: completed[index], totalSets: current.sets, nextStep: next)
    }
    var totalSets: Int { exercises.reduce(0) { $0 + $1.sets } }
    var completedSets: Int { completed.reduce(0, +) }
    var nextName: String { index + 1 < exercises.count ? exercises[index + 1].name : "最后一个动作" }
    func secondsLeft(at now: Date) -> TimeInterval {
        if phase == .paused { return max(0, remaining) }
        return max(0, restEnd?.timeIntervalSince(now) ?? 0)
    }
    mutating func advanceAfterSet() {
        timerID = nil; restEnd = nil; remaining = 0; reminderRegistered = false
        if completed[index] >= current.sets {
            if index + 1 < exercises.count { index += 1; phase = .training }
            else { phase = .completed }
        } else { phase = .training }
    }
}
