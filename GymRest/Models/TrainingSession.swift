import Foundation

enum TrainingPhase: String, Codable, Sendable { case idle, training, resting, paused, completed }

struct TrainingSession: Codable, Equatable, Sendable {
    var sessionID: UUID? = UUID()
    // Rotates on each durable state change; old Live Activity buttons cannot be replayed.
    var interactionID: UUID? = UUID()
    var startedAt: Date? = Date()
    let planID: UUID
    let planName: String
    var exercises: [ExerciseSpec]
    var originalExercises: [ExerciseSpec]?
    var performedNames: [[String]]?
    var performances: [[SetPerformance]]?
    var setDrafts: [SetValues]?
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
        let exercises = ExerciseNames.standardize(exercises)
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
        guard !planName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, planName.count <= 100 else { throw TrainingError.invalidSession }
        if phase == .training {
            guard completed[index] < current.sets, timerID == nil, restEnd == nil, !reminderRegistered else { throw TrainingError.invalidSession }
        } else {
            guard completed[index] > 0, (1...86400).contains(originalRest) else { throw TrainingError.invalidSession }
        }
        for exercise in exercises { try exercise.validate() }
        if let originalExercises {
            guard originalExercises.count == exercises.count,
                  zip(originalExercises, exercises).allSatisfy({ $0.0.id == $0.1.id && $0.0.sets == $0.1.sets && $0.0.restAfterLastSet == $0.1.restAfterLastSet && $0.0.transitionRestSeconds == $0.1.transitionRestSeconds }) else { throw TrainingError.invalidSession }
            for exercise in originalExercises { try exercise.validate() }
        }
        if let setDrafts {
            guard setDrafts.count == exercises.count else { throw TrainingError.invalidSession }
            for values in setDrafts { try values.validate() }
        }
        if let performances {
            guard performances.count == exercises.count, zip(performances, completed).allSatisfy({ $0.0.count == $0.1 }) else { throw TrainingError.invalidSession }
            for values in performances { for set in values { try set.validate() } }
        }
        if let performedNames {
            guard performedNames.count == exercises.count,
                  zip(performedNames, completed).allSatisfy({ $0.0.count == $0.1 }) else { throw TrainingError.invalidSession }
        }
    }
    var current: ExerciseSpec { exercises[index] }
    var currentSetValues: SetValues { setDrafts?[index] ?? current.prescription ?? SetValues() }
    mutating func preparePerformanceStorage() {
        if setDrafts == nil { setDrafts = exercises.map { $0.prescription ?? SetValues() } }
        if performances == nil {
            performances = exercises.enumerated().map { i, exercise in
                (0..<completed[i]).map { set in
                    let name = performedNames?[i][set] ?? exercise.name
                    return SetPerformance(exerciseName: name, catalogID: nil, values: nil, profileKey: nil, completedAt: nil)
                }
            }
        }
    }
    var isTransitionRest: Bool {
        (phase == .resting || phase == .paused) && completed[index] == current.sets && index + 1 < exercises.count
    }
    func restDuration(afterSet set: Int) -> Int? {
        if set < current.sets { return current.rest(afterSet: set) }
        if index + 1 < exercises.count, let seconds = current.transitionRestSeconds {
            return seconds > 0 ? seconds : nil
        }
        return current.restAfterLastSet ? current.rest(afterSet: set) : nil
    }
    var restContext: RestContext {
        let next: String
        if completed[index] < current.sets { next = "下一组：第 \(completed[index] + 1) / \(current.sets) 组" }
        else if index + 1 < exercises.count { next = "下一动作：" + exercises[index + 1].name }
        else { next = "本次训练即将完成" }
        return RestContext(planName: planName, exerciseName: current.name, completedSet: completed[index], totalSets: current.sets, nextStep: next,
                           kind: isTransitionRest ? "transition" : "set")
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
