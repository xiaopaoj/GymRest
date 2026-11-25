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
            for (position, name) in ["胸部训练", "背部训练", "腿部训练", "肩部训练", "手臂训练"].enumerated() {
                context.insert(try TrainingPlan(name: name, position: position))
            }
            try context.save()
        }
    }
    func load() throws -> TrainingSession? {
        guard let record = try context.fetch(FetchDescriptor<ActiveTraining>()).first else { return nil }
        let session = try JSONDecoder().decode(TrainingSession.self, from: record.payload)
        try session.validate()
        return session
    }
    func save(_ session: TrainingSession?) throws {
        let records = try context.fetch(FetchDescriptor<ActiveTraining>())
        if let session, session.phase != .completed {
            let data = try JSONEncoder().encode(session)
            if let record = records.first { record.payload = data }
            else { context.insert(ActiveTraining(payload: data)) }
        } else { for record in records { context.delete(record) } }
        try context.save()
    }
}
