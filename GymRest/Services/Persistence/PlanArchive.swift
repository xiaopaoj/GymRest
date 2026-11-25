import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct PlanArchive: Codable {
    var version = 1
    var plans: [Entry]
    struct Entry: Codable {
        var id: UUID
        var name: String
        var exercises: [ExerciseSpec]
    }
    func validate() throws {
        guard version == 1 else { throw ArchiveFailure.invalid("不支持的文件版本。") }
        guard Set(plans.map(\.id)).count == plans.count else { throw ArchiveFailure.invalid("计划ID重复。") }
        for plan in plans {
            guard !plan.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, plan.name.count <= 100,
                  Set(plan.exercises.flatMap { [$0.id] + $0.alternatives.map(\.id) }).count == plan.exercises.reduce(0, { $0 + 1 + $1.alternatives.count }) else {
                throw ArchiveFailure.invalid("计划名称不合法或动作ID重复。")
            }
            for exercise in plan.exercises { try exercise.validate() }
        }
    }
    static func decode(_ data: Data) throws -> PlanArchive {
        guard data.count <= 10 * 1024 * 1024 else { throw ArchiveFailure.invalid("单次导入文件不能超过10MB。") }
        let archive = try JSONDecoder().decode(Self.self, from: data)
        try archive.validate(); return archive
    }
    @MainActor static func export(plans: [TrainingPlan]) throws -> Data {
        let archive = PlanArchive(plans: try plans.map { Entry(id: $0.id, name: $0.name, exercises: try $0.exercises()) })
        try archive.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(archive)
    }
    @MainActor func append(to context: ModelContext) throws {
        try validate()
        // Build every new value before insertion: invalid input never imports a partial library.
        let position = (try context.fetch(FetchDescriptor<TrainingPlan>()).map(\.position).max() ?? -1) + 1
        let additions = try plans.enumerated().map { offset, entry in
            var exercises = entry.exercises
            for i in exercises.indices {
                exercises[i].id = UUID()
                for j in exercises[i].alternatives.indices { exercises[i].alternatives[j].id = UUID() }
            }
            return try TrainingPlan(name: entry.name, position: position + offset, exercises: exercises)
        }
        do {
            for plan in additions { context.insert(plan) }
            try context.save()
        } catch { context.rollback(); throw error }
    }
}
enum ArchiveFailure: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}
struct PlanFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
