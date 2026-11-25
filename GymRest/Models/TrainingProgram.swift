import Foundation
import SwiftData

@Model final class TrainingProgram {
    @Attribute(.unique) var id: UUID
    var name: String
    var position: Int
    init(id: UUID = UUID(), name: String, position: Int) {
        self.id = id; self.name = name; self.position = position
    }
}

@MainActor enum ProgramLibrary {
    static func organize(name: String, days: [TrainingPlan], existing: TrainingProgram?, convertBlank: TrainingPlan?, context: ModelContext) throws {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard existing != nil || (!title.isEmpty && title.count <= 100) else { throw ArchiveFailure.invalid("计划名称须为1–100字。") }
        if let blank = convertBlank {
            guard existing == nil, blank.programID == nil, try blank.exercises().isEmpty, !days.contains(where: { $0.id == blank.id }) else {
                throw ArchiveFailure.invalid("只能将未选择的空白项目转为上层计划。")
            }
        }
        do {
            let parent: TrainingProgram
            if let existing { parent = existing }
            else {
                let next = (try context.fetch(FetchDescriptor<TrainingProgram>()).map(\.position).max() ?? -1) + 1
                parent = TrainingProgram(id: convertBlank?.id ?? UUID(), name: title, position: next)
                context.insert(parent)
            }
            let currentDays = try context.fetch(FetchDescriptor<TrainingPlan>()).filter { $0.programID == parent.id }
            var next = (currentDays.map(\.position).max() ?? -1) + 1
            for day in days where day.programID != parent.id { day.programID = parent.id; day.position = next; next += 1 }
            if let convertBlank { context.delete(convertBlank) }
            try context.save()
        } catch { context.rollback(); throw error }
    }
    static func duplicate(_ program: TrainingProgram, context: ModelContext) throws {
        let days = try context.fetch(FetchDescriptor<TrainingPlan>(sortBy: [SortDescriptor(\TrainingPlan.position)]))
            .filter { $0.programID == program.id }
        var archive = try PlanArchive.decode(PlanArchive.export(plans: days, programs: [program]))
        archive.programs?[0].name = String(program.name.prefix(97)) + " 副本"
        try archive.append(to: context)
    }
    static func detachAndDelete(_ program: TrainingProgram, context: ModelContext) throws {
        do {
            for day in try context.fetch(FetchDescriptor<TrainingPlan>()) where day.programID == program.id { day.programID = nil }
            context.delete(program); try context.save()
        } catch { context.rollback(); throw error }
    }
}
