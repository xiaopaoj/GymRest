import Foundation

struct TrainingComparison {
    struct Session: Identifiable {
        let id: UUID
        let date: Date
        var values: [SetValues]
    }
    struct Profile: Identifiable {
        let id: String
        let name: String
        let unit: LoadUnit
        let kind: LoadKind
        let equipmentNote: String
        var sessions: [Session]
    }
    @MainActor static func profiles(_ records: [TrainingRecord]) -> [Profile] {
        var groups: [String: Profile] = [:]
        for record in records.sorted(by: { $0.endedAt > $1.endedAt }) {
            guard let sets = try? record.performances() else { continue }
            for set in sets.flatMap({ $0 }) {
                guard let values = set.values, values.weight != nil || values.repetitions != nil || values.durationSeconds != nil else { continue }
                let exercise = ExerciseSpec(name: set.exerciseName, catalogID: set.catalogID)
                let key = exercise.profileKey(for: values)
                if groups[key] == nil {
                    groups[key] = Profile(id: key, name: set.exerciseName, unit: values.unit, kind: values.kind,
                                          equipmentNote: values.equipmentNote, sessions: [])
                }
                if let index = groups[key]?.sessions.firstIndex(where: { $0.id == record.id }) {
                    groups[key]?.sessions[index].values.append(values)
                } else {
                    groups[key]?.sessions.append(Session(id: record.id, date: record.endedAt, values: [values]))
                }
            }
        }
        return groups.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
