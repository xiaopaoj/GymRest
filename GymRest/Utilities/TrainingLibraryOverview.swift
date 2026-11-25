import Foundation

struct TrainingDaySummary {
    let name: String
    let exerciseCount: Int?
    let setCount: Int?
    var isEmpty: Bool { exerciseCount == 0 }
    init(day: TrainingPlan) {
        name = day.name
        do {
            let exercises = try day.exercises()
            for exercise in exercises { try exercise.validate() }
            exerciseCount = exercises.count; setCount = exercises.reduce(0) { $0 + $1.sets }
        } catch { exerciseCount = nil; setCount = nil }
    }
}

// One pass per view evaluation, with no mutation or shared cache during rendering.
struct TrainingLibraryOverview {
    let summaries: [UUID: TrainingDaySummary]
    let grouped: [UUID: [TrainingPlan]]
    let unassigned: [TrainingPlan]
    let templateIDs: Set<UUID>
    init(programs: [TrainingProgram], days: [TrainingPlan]) {
        let validParents = Set(programs.map(\.id))
        var summaries: [UUID: TrainingDaySummary] = [:]
        var grouped: [UUID: [TrainingPlan]] = [:]
        var unassigned: [TrainingPlan] = []
        for day in days {
            summaries[day.id] = TrainingDaySummary(day: day)
            if let id = day.programID, validParents.contains(id) { grouped[id, default: []].append(day) }
            else { unassigned.append(day) }
        }
        self.summaries = summaries; self.grouped = grouped; self.unassigned = unassigned
        templateIDs = Set(programs.compactMap { parent in
            guard let children = grouped[parent.id], !children.isEmpty,
                  children.allSatisfy({ summaries[$0.id]?.isEmpty == true }) else { return nil }
            return parent.id
        })
    }
}
