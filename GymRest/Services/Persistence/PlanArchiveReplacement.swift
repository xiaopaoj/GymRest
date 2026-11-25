import Foundation
import SwiftData

extension PlanArchive {
    enum ReplacementScope: Equatable { case program(UUID), library }
    struct ReplacementPreview: Equatable {
        struct Program: Equatable {
            let id: UUID
            let name: String
            let position: Int
            let weeklySessions: Int?
        }
        struct Day: Equatable {
            let id: UUID
            let name: String
            let position: Int
            let programID: UUID?
            let exercises: Data
        }
        let scope: ReplacementScope
        let source: Data
        let programs: [Program]
        let days: [Day]
        var targetName: String {
            switch scope {
            case .program: programs.first?.name ?? "所选计划"
            case .library: "全部本地计划（含未归类训练日）"
            }
        }
    }

    @MainActor func previewReplacement(in context: ModelContext, scope: ReplacementScope) throws -> ReplacementPreview {
        try validate()
        guard !plans.isEmpty else { throw ArchiveFailure.invalid("覆盖文件须至少包含一个训练日。") }
        guard !context.hasChanges else { throw ArchiveFailure.invalid("请先保存或取消当前编辑，再预览覆盖导入。") }
        let allPrograms = try context.fetch(FetchDescriptor<TrainingProgram>())
        let allDays = try context.fetch(FetchDescriptor<TrainingPlan>())
        let parents: [TrainingProgram]
        let days: [TrainingPlan]
        switch scope {
        case .program(let id):
            guard let parent = allPrograms.first(where: { $0.id == id }) else { throw ArchiveFailure.invalid("覆盖目标计划已不存在，请重新选择。") }
            parents = [parent]; days = allDays.filter { $0.programID == id }
        case .library: parents = allPrograms; days = allDays
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return ReplacementPreview(scope: scope, source: try encoder.encode(self),
            programs: parents.sorted { $0.id.uuidString < $1.id.uuidString }.map { .init(id: $0.id, name: $0.name, position: $0.position, weeklySessions: $0.weeklySessions) },
            days: days.sorted { $0.id.uuidString < $1.id.uuidString }.map {
                .init(id: $0.id, name: $0.name, position: $0.position, programID: $0.programID, exercises: $0.exerciseData)
            })
    }

    @MainActor func replace(in context: ModelContext, confirmed preview: ReplacementPreview,
                            newProgramName: String? = nil, beforeCommit: () throws -> Void = {}) throws {
        let current = try previewReplacement(in: context, scope: preview.scope)
        guard current == preview else { throw ArchiveFailure.invalid("本地计划已发生变化，请重新预览并确认覆盖范围。") }
        let allPrograms = try context.fetch(FetchDescriptor<TrainingProgram>())
        let allDays = try context.fetch(FetchDescriptor<TrainingPlan>())
        let coveredIDs = Set(preview.days.map(\.id))
        let target: TrainingProgram?
        switch preview.scope {
        case .program(let id): target = allPrograms.first { $0.id == id }
        case .library: target = nil
        }
        do {
            for day in allDays where coveredIDs.contains(day.id) { context.delete(day) }
            if preview.scope == .library {
                for program in allPrograms { context.delete(program) }
            }
            // append constructs fresh values and commits once. Its rollback plus this
            // catch also restores deletions if validation/construction or saving fails.
            try append(to: context, targetProgram: target,
                       newProgramName: target == nil ? newProgramName : nil, beforeCommit: beforeCommit)
        } catch { context.discardPendingChanges(); throw error }
    }
}
