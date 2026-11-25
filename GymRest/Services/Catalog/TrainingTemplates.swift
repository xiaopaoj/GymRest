import Foundation
import SwiftData

struct TrainingTemplate: Identifiable, Sendable {
    struct Day: Sendable { let name: String; let slots: [String] }
    let id: String
    let name: String
    let detail: String
    let days: [Day]
    func key(day: Int, slot: Int) -> String { "\(id):\(day):\(slot)" }
    static var all: [Self] { [
        .init(id: "ppl", name: "三分化 · 推／拉／腿", detail: "三个训练日循环，可按恢复情况安排休息，不等于每周必须练三天。", days: [
            .init(name: "推 · 胸／肩／三头", slots: ["barbell-bench","incline-dumbbell","dumbbell-press","dumbbell-lateral","triceps-pushdown"]),
            .init(name: "拉 · 背／后束／二头", slots: ["lat-pulldown","cable-row","dumbbell-rear","dumbbell-curl"]),
            .init(name: "腿 · 下肢／核心", slots: ["back-squat","barbell-rdl","seated-leg-curl","standing-calf","crunch"])
        ]),
        .init(id: "five", name: "五分化 · 胸／背／腿／肩／手臂", detail: "五个训练日循环，训练日顺序与休息日可自行调整；创建后仍可编辑。", days: [
            .init(name: "胸部训练", slots: ["barbell-bench","incline-dumbbell","cable-fly"]),
            .init(name: "背部训练", slots: ["lat-pulldown","barbell-row","cable-row"]),
            .init(name: "腿部训练", slots: ["back-squat","barbell-rdl","leg-extension","seated-leg-curl","standing-calf"]),
            .init(name: "肩部训练", slots: ["dumbbell-press","dumbbell-lateral","dumbbell-rear"]),
            .init(name: "手臂／核心", slots: ["barbell-curl","hammer-curl","triceps-pushdown","dumbbell-triceps","crunch"])
        ])
    ] }
    func options(baseID: String, catalog: ExerciseCatalog, equipment: Set<String>) -> [CatalogExercise] {
        guard let base = catalog.item(baseID) else { return [] }
        return ([base] + catalog.alternatives(to: base)).filter { Set($0.equipment).isSubset(of: equipment) }
    }
    func resolvedSelections(catalog: ExerciseCatalog, equipment: Set<String>, selections: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (dayIndex, day) in days.enumerated() {
            var used: Set<String> = []
            for (slotIndex, base) in day.slots.enumerated() {
                let slotKey = key(day: dayIndex, slot: slotIndex)
                let choices = options(baseID: base, catalog: catalog, equipment: equipment)
                // Honor a deliberate selection. Automatic fallbacks favor variety when available.
                if let item = choices.first(where: { $0.id == selections[slotKey] }) ?? choices.first(where: { !used.contains($0.id) }) ?? choices.first {
                    result[slotKey] = item.id; used.insert(item.id)
                }
            }
        }
        return result
    }
    func build(catalog: ExerciseCatalog, equipment: Set<String>, selections: [String: String], priority: MuscleGroup?) throws -> [[ExerciseSpec]] {
        let resolved = resolvedSelections(catalog: catalog, equipment: equipment, selections: selections)
        return try days.enumerated().map { dayIndex, day in
            let exercises = try day.slots.enumerated().map { slotIndex, base in
                let choices = options(baseID: base, catalog: catalog, equipment: equipment)
                let selected = resolved[key(day: dayIndex, slot: slotIndex)]
                guard let item = choices.first(where: { $0.id == selected }) else { throw CatalogError.unavailable }
                return item.spec(alternatives: Array(catalog.alternatives(to: item, equipment: equipment).prefix(4)))
            }
            return TrainingOrderAdvice.suggest(exercises, catalog: catalog, priority: priority).map(\.exercise)
        }
    }
    @MainActor func install(catalog: ExerciseCatalog, equipment: Set<String>, selections: [String: String], priority: MuscleGroup?,
                            name: String, weeklySessions: Int? = nil, context: ModelContext, beforeCommit: () throws -> Void = {}) throws {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 100 else { throw TrainingError.invalidExercise }
        if let weeklySessions, !(1...7).contains(weeklySessions) { throw CatalogError.invalid }
        let values = try build(catalog: catalog, equipment: equipment, selections: selections, priority: priority)
        let position = (try context.fetch(FetchDescriptor<TrainingProgram>()).map(\.position).max() ?? -1) + 1
        let program = TrainingProgram(name: title, position: position, weeklySessions: weeklySessions)
        let additions = try zip(days, values).enumerated().map { index, pair in
            let day = try TrainingPlan(name: pair.0.name, position: index, exercises: pair.1)
            day.programID = program.id; return day
        }
        guard !context.hasChanges else { throw ArchiveFailure.invalid("请先保存当前编辑，再创建模板计划。") }
        do {
            context.insert(program)
            for day in additions { context.insert(day) }
            try beforeCommit(); try context.save()
        } catch { context.discardPendingChanges(); throw error }
    }
}
