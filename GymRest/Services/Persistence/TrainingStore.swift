import Foundation
import SwiftData

@MainActor final class TrainingStore {
    let context: ModelContext
    let preferences: LibraryPreferences
    init(container: ModelContainer) throws {
        context = ModelContext(container)
        context.autosaveEnabled = false
        if let existing = try context.fetch(FetchDescriptor<LibraryPreferences>()).first {
            preferences = existing
        } else {
            preferences = LibraryPreferences()
            context.insert(preferences)
            let program = TrainingProgram(name: "五分化模板", position: 0)
            context.insert(program)
            for (position, name) in ["胸部训练", "背部训练", "腿部训练", "肩部训练", "手臂训练"].enumerated() {
                let day = try TrainingPlan(name: name, position: position)
                day.programID = program.id; context.insert(day)
            }
            try context.save()
        }
    }
    func load() throws -> TrainingSession? {
        guard let record = try context.fetch(FetchDescriptor<ActiveTraining>()).first else { return nil }
        var session = try JSONDecoder().decode(TrainingSession.self, from: record.payload)
        if session.sessionID == nil { session.sessionID = UUID() }
        try session.validate()
        return session
    }
    func lastValues(for exercise: ExerciseSpec, matching profile: SetValues) throws -> SetValues? {
        let key = exercise.profileKey(for: profile)
        var lookup = FetchDescriptor<TrainingRecord>(sortBy: [SortDescriptor(\TrainingRecord.endedAt, order: .reverse)])
        lookup.fetchLimit = 50
        for record in try context.fetch(lookup) {
            // Legacy records have no measured loads. A corrupt record remains visible in
            // history; it must not prevent starting another training session.
            guard let sets = try? record.performances() else { continue }
            for set in sets.flatMap({ $0 }).reversed() where set.profileKey == key {
                if let values = set.values, (try? values.validate()) != nil { return values }
            }
        }
        return nil
    }
    func suggestedValues(for exercise: ExerciseSpec) throws -> SetValues {
        var planned = exercise.prescription ?? SetValues()
        if let last = try lastValues(for: exercise, matching: planned) {
            if planned.weight == nil { planned.weight = last.weight }
            if planned.repetitions == nil { planned.repetitions = last.repetitions }
        }
        return planned
    }
    private func archive(_ session: TrainingSession, at end: Date) throws {
        let id = session.sessionID ?? session.planID
        var lookup = FetchDescriptor<TrainingRecord>(predicate: #Predicate { $0.id == id })
        lookup.fetchLimit = 1
        guard try context.fetch(lookup).isEmpty else { return }
        context.insert(try TrainingRecord(session: session, end: end))
    }
    func finish(_ session: TrainingSession?, at date: Date) throws {
        // Archive and remove the active state in one SwiftData save.
        do {
            if let session { try archive(session, at: date) }
            for record in try context.fetch(FetchDescriptor<ActiveTraining>()) { context.delete(record) }
            try context.save()
        } catch { context.discardPendingChanges(); throw error }
    }
    func save(_ session: TrainingSession?, at date: Date = Date()) throws {
        do {
            let records = try context.fetch(FetchDescriptor<ActiveTraining>())
            if let session, session.phase != .completed {
                try session.validate()
                let data = try JSONEncoder().encode(session)
                if let record = records.first { record.payload = data }
                else { context.insert(ActiveTraining(payload: data)) }
            } else {
                if let session { try archive(session, at: date) }
                for record in records { context.delete(record) }
            }
            try context.save()
        } catch { context.discardPendingChanges(); throw error }
    }
}
