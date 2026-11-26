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
            try context.save()
        }
        try Self.removeLegacyPlaceholders(in: context, preferences: preferences)
        try Self.standardizeStoredExerciseNames(in: context)
    }
    static func standardizeStoredExerciseNames(in context: ModelContext, beforeCommit: () throws -> Void = {}) throws {
        guard !context.hasChanges else { throw ArchiveFailure.invalid("请先保存已有编辑，再统一动作名称。") }
        var updates: [(TrainingPlan, [ExerciseSpec])] = []
        for day in try context.fetch(FetchDescriptor<TrainingPlan>()) {
            guard let original = try? day.exercises() else { continue }
            let revised = ExerciseNames.standardize(original)
            guard revised != original else { continue }
            // Invalid legacy plans remain readable as errors, never rewritten by cleanup.
            do { for exercise in revised { try exercise.validate() } } catch { continue }
            updates.append((day, revised))
        }
        guard !updates.isEmpty else { return }
        do {
            for (day, exercises) in updates { try day.setExercises(exercises) }
            try beforeCommit()
            try context.save()
        } catch { context.discardPendingChanges(); throw error }
    }
    /// One-time removal of known legacy seed rows, never a general empty-day sweep.
    static func removeLegacyPlaceholders(in context: ModelContext, preferences: LibraryPreferences,
                                         beforeCommit: () throws -> Void = {}) throws {
        guard preferences.legacyPlaceholdersRemoved != true else { return }
        guard !context.hasChanges else { throw ArchiveFailure.invalid("请先保存已有编辑，再清理旧版空白项目。") }
        let names: Set<String> = ["胸部训练", "背部训练", "腿部训练", "肩部训练", "手臂训练"]
        let programs = try context.fetch(FetchDescriptor<TrainingProgram>())
        let seedParents = programs.filter { $0.name == "五分化模板" }
        let seedIDs = Set(seedParents.map(\.id))
        let days = try context.fetch(FetchDescriptor<TrainingPlan>())
        let removed = days.filter { day in
            names.contains(day.name) && (day.programID == nil || day.programID.map { seedIDs.contains($0) } == true)
                && (try? day.exercises().isEmpty) == true
        }
        let removedIDs = Set(removed.map(\.id))
        do {
            for day in removed { context.delete(day) }
            for parent in seedParents where !days.contains(where: { $0.programID == parent.id && !removedIDs.contains($0.id) }) {
                context.delete(parent)
            }
            preferences.legacyPlaceholdersRemoved = true
            try beforeCommit()
            try context.save()
        } catch { context.discardPendingChanges(); throw error }
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
            for set in sets.flatMap({ $0 }).reversed() where set.profileKey.map({ ExerciseNames.canonicalProfileKey($0) }) == key {
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
