import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct PlanArchive: Codable {
    var version = 1
    var plans: [Entry]
    var programs: [ProgramEntry]? = nil
    struct ProgramEntry: Codable {
        var id: UUID
        var name: String
        var weeklySessions: Int? = nil
    }
    struct Entry: Codable {
        var id: UUID
        var name: String
        var exercises: [ExerciseSpec]
        var programID: UUID? = nil
    }
    func validate() throws {
        guard version == 1 || version == 2 || version == 3 else { throw ArchiveFailure.invalid("不支持的文件版本。") }
        guard Set(plans.map(\.id)).count == plans.count else { throw ArchiveFailure.invalid("计划ID重复。") }
        let parents = programs ?? []
        guard Set(parents.map(\.id)).count == parents.count else { throw ArchiveFailure.invalid("上层计划ID重复。") }
        for parent in parents {
            if let sessions = parent.weeklySessions, !(1...7).contains(sessions) { throw ArchiveFailure.invalid("每周目标须为1–7次。") }
            guard !parent.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, parent.name.count <= 100 else { throw ArchiveFailure.invalid("上层计划名称须为1–100字。") }
        }
        for (dayIndex, plan) in plans.enumerated() {
            if let parent = plan.programID, !parents.contains(where: { $0.id == parent }) { throw ArchiveFailure.invalid("plans[\(dayIndex)].programID：训练日「\(plan.name)」引用了不存在的上层计划。") }
            guard !plan.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, plan.name.count <= 100 else {
                throw ArchiveFailure.invalid("计划名称不合法或动作ID重复。")
            }
            var identifiers = Set<UUID>()
            for (exerciseIndex, exercise) in plan.exercises.enumerated() {
                guard identifiers.insert(exercise.id).inserted else { throw ArchiveFailure.invalid("plans[\(dayIndex)].exercises[\(exerciseIndex)].id：动作ID重复。") }
                for (alternativeIndex, alternative) in exercise.alternatives.enumerated() {
                    guard identifiers.insert(alternative.id).inserted else { throw ArchiveFailure.invalid("plans[\(dayIndex)].exercises[\(exerciseIndex)].alternatives[\(alternativeIndex)].id：动作ID重复。") }
                }
                do { try PlanImportValidation.exercise(exercise, path: "plans[\(dayIndex)].exercises[\(exerciseIndex)]") }
                catch { throw ArchiveFailure.invalid("第 \(dayIndex + 1) 个训练日「\(plan.name)」第 \(exerciseIndex + 1) 个动作「\(exercise.name)」：" + error.localizedDescription) }
            }
        }
    }
    static func decode(_ data: Data) throws -> PlanArchive {
        guard data.count <= 10 * 1024 * 1024 else { throw ArchiveFailure.invalid("单次导入文件不能超过10MB。") }
        let cleaned = PlanImportSupport.cleaned(data)
        if let root = try? JSONSerialization.jsonObject(with: cleaned) as? [String: Any], root["format"] as? String == "GymRestBackup" {
            throw ArchiveFailure.invalid("这是完整备份，请到设置的「完整备份与恢复」页面打开。")
        }
        var archive: Self
        do { archive = try JSONDecoder().decode(Self.self, from: cleaned) }
        catch { throw ArchiveFailure.invalid(PlanImportSupport.message(error)) }
        try archive.validate()
        for index in archive.plans.indices { archive.plans[index].exercises = ExerciseNames.standardize(archive.plans[index].exercises) }
        return archive
    }
    @MainActor static func export(plans: [TrainingPlan], programs: [TrainingProgram] = []) throws -> Data {
        let parents = programs.map { ProgramEntry(id: $0.id, name: $0.name, weeklySessions: $0.weeklySessions) }
        let entries = try plans.map { day in
            Entry(id: day.id, name: day.name, exercises: try day.exercises(), programID: parents.contains(where: { $0.id == day.programID }) ? day.programID : nil)
        }
        var extended = parents.contains { $0.weeklySessions != nil }
        for entry in entries {
            for exercise in entry.exercises {
                if exercise.catalogID != nil || exercise.prescription != nil { extended = true }
                for alternative in exercise.alternatives {
                    if alternative.catalogID != nil || alternative.prescription != nil { extended = true }
                }
            }
        }
        let archive = PlanArchive(version: extended ? 3 : parents.isEmpty ? 1 : 2, plans: entries, programs: parents.isEmpty ? nil : parents)
        try archive.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(archive)
    }
    @MainActor func append(to context: ModelContext, targetProgram: TrainingProgram? = nil, newProgramName: String? = nil,
                           beforeCommit: () throws -> Void = {}) throws {
        try validate()
        if plans.isEmpty && (programs ?? []).isEmpty { return }
        // Build every new value before insertion: invalid input never imports a partial library.
        var parentMap: [UUID: UUID] = [:]
        var newParents: [TrainingProgram] = []
        let parentPosition = (try context.fetch(FetchDescriptor<TrainingProgram>()).map(\.position).max() ?? -1) + 1
        var defaultParentID = targetProgram?.id
        if targetProgram == nil {
            for entry in programs ?? [] {
                let parent = TrainingProgram(name: entry.name, position: parentPosition + newParents.count, weeklySessions: entry.weeklySessions)
                parentMap[entry.id] = parent.id; newParents.append(parent)
            }
            if let newProgramName, plans.contains(where: { $0.programID == nil }) || (programs ?? []).isEmpty {
                let title = newProgramName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty, title.count <= 100 else { throw ArchiveFailure.invalid("导入目标计划名称须为1–100字。") }
                let parent = TrainingProgram(name: title, position: parentPosition + newParents.count)
                defaultParentID = parent.id; newParents.append(parent)
            }
        }
        let position = (try context.fetch(FetchDescriptor<TrainingPlan>()).map(\.position).max() ?? -1) + 1
        let additions = try plans.enumerated().map { offset, entry in
            var exercises = entry.exercises
            for i in exercises.indices {
                exercises[i].id = UUID()
                for j in exercises[i].alternatives.indices { exercises[i].alternatives[j].id = UUID() }
            }
            let day = try TrainingPlan(name: entry.name, position: position + offset, exercises: exercises)
            day.programID = targetProgram?.id ?? entry.programID.flatMap { parentMap[$0] } ?? defaultParentID
            return day
        }
        do {
            for parent in newParents { context.insert(parent) }
            for plan in additions { context.insert(plan) }
            try beforeCommit()
            try context.save()
        } catch { context.discardPendingChanges(); throw error }
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
