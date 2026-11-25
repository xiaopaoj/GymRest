import SwiftUI
import SwiftData

struct TrainingTemplateView: View {
    var body: some View {
        List {
            Section {
                Text("选一个结构，再按可用器材和当天重点挑选动作。模板会新建为你的计划，之后可自由编辑。")
                    .foregroundStyle(.secondary)
            }
            ForEach(TrainingTemplate.all) { template in
                NavigationLink { TemplateCustomizeView(template: template) } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(template.name, systemImage: "square.stack.3d.up.fill").font(.headline).foregroundStyle(.primary)
                        Text(template.detail).font(.subheadline).foregroundStyle(.secondary)
                        Text("\(template.days.count) 个训练日 · 动作可替换 · 含休息配置").font(.caption).foregroundStyle(.orange)
                    }.padding(.vertical, 12)
                }
            }
            Section { Text("首版建议以动作质量与恢复为依据自行安排训练日和休息日，不会因选择五分化就认定训练效果优于三分化。")
                    .font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("训练模板")
    }
}
private struct TemplateCustomizeView: View {
    @Environment(\.modelContext) private var context
    let template: TrainingTemplate
    @State private var catalog: ExerciseCatalog?
    @State private var name = ""
    @State private var weeklySessions = 3
    @State private var equipment = Set(ExerciseCatalog.equipmentNames.keys)
    @State private var selections: [String: String] = [:]
    @State private var priority = ""
    @State private var error: String?
    @State private var created = false
    var body: some View {
        Form {
            Section("计划设置") {
                TextField("计划名称", text: $name)
                Stepper("每周目标 \(weeklySessions) 次", value: $weeklySessions, in: 1...7)
                Text("目标次数仅作安排参考，不固定星期；按训练日循环并自行安排恢复。")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("重点部位", selection: $priority) {
                    Text("均衡安排").tag("")
                    ForEach(MuscleGroup.allCases) { Text($0.title).tag($0.rawValue) }
                }
                DisclosureGroup("可用器材 · \(equipment.count) 类") {
                    ForEach(ExerciseCatalog.equipmentNames.keys.sorted(), id: \.self) { id in
                        Toggle(ExerciseCatalog.equipmentNames[id]!, isOn: Binding(get: { equipment.contains(id) }, set: { selected in
                            if selected { equipment.insert(id) } else { equipment.remove(id) }
                        }))
                    }
                }
            }
            if let catalog {
                ForEach(Array(template.days.enumerated()), id: \.offset) { dayIndex, day in
                    Section(day.name) {
                        ForEach(Array(day.slots.enumerated()), id: \.offset) { slotIndex, base in
                            let choices = template.options(baseID: base, catalog: catalog, equipment: equipment)
                            let key = template.key(day: dayIndex, slot: slotIndex)
                            let resolved = template.resolvedSelections(catalog: catalog, equipment: equipment, selections: selections)
                            let selected = choices.first(where: { $0.id == resolved[key] })
                            if let selected {
                                Picker(catalog.item(base)?.name ?? "动作", selection: Binding(get: { selected.id }, set: { selections[key] = $0 })) {
                                    ForEach(choices) { Text($0.name).tag($0.id) }
                                }
                                NavigationLink { CatalogExerciseDetail(item: selected, catalog: catalog) } label: {
                                    Text("查看 \(selected.name) 的肌群、器材与演示").font(.caption)
                                }
                            } else { Text("\(catalog.item(base)?.name ?? base)：当前器材无合适动作").foregroundStyle(.orange) }
                        }
                    }
                }
                if let preview = try? template.build(catalog: catalog, equipment: equipment, selections: selections, priority: MuscleGroup(rawValue: priority)) {
                    Section("创建后的顺序预览") {
                        ForEach(Array(preview.enumerated()), id: \.offset) { index, exercises in
                            Text(template.days[index].name).font(.headline)
                            Text(exercises.map(\.name).joined(separator: " → ")).font(.subheadline)
                            Text("共 \(exercises.reduce(0) { $0 + $1.sets }) 组；具体休息与次数可在创建后编辑。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("重点部位优先，其余多关节动作优先；不保证重新排序必然提升增肌效果。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            if created { Section { Label("已加入我的计划，可返回计划首页查看", systemImage: "checkmark.circle.fill").foregroundStyle(.green) } }
        }
        .navigationTitle("定制模板").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button(created ? "已创建" : "创建为我的计划") {
                guard !created else { return }
                do {
                    guard let catalog else { throw CatalogError.invalid }
                    try template.install(catalog: catalog, equipment: equipment, selections: selections,
                        priority: MuscleGroup(rawValue: priority), name: name, weeklySessions: weeklySessions, context: context)
                    created = true; error = nil
                } catch { self.error = error.localizedDescription }
            }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity).padding().background(.regularMaterial)
                .disabled(created || catalog == nil || !canBuild)
        }
        .task {
            guard catalog == nil else { return }
            name = template.name; weeklySessions = template.days.count
            do { catalog = try ExerciseCatalog.bundled() } catch { self.error = error.localizedDescription }
        }
    }
    private var canBuild: Bool {
        guard let catalog else { return false }
        return (try? template.build(catalog: catalog, equipment: equipment, selections: selections, priority: MuscleGroup(rawValue: priority))) != nil
    }
}
struct TrainingOrderView: View {
    @Environment(\.dismiss) private var dismiss
    let exercises: [ExerciseSpec]
    let apply: @MainActor ([ExerciseSpec]) async throws -> Void
    @State private var priority = ""
    @State private var catalog: ExerciseCatalog?
    @State private var error: String?
    @State private var applying = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("当天重点", selection: $priority) {
                        Text("均衡安排").tag("")
                        ForEach(MuscleGroup.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Text("先安排重点部位，再优先多关节动作。自定义未关联动作保留位置；训练中仅调整未开始动作，已完成组不变。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("原顺序") { Text(exercises.map(\.name).joined(separator: " → ")).font(.subheadline) }
                if let catalog {
                    let suggestions = TrainingOrderAdvice.suggest(exercises, catalog: catalog, priority: MuscleGroup(rawValue: priority))
                    Section("建议顺序") {
                        ForEach(Array(suggestions.enumerated()), id: \.element.exercise.id) { index, suggestion in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(index + 1). " + suggestion.exercise.name).font(.headline)
                                Text(suggestion.reason).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section {
                        Button("采用建议顺序") {
                            Task { @MainActor in
                                applying = true; defer { applying = false }
                                do { try await apply(suggestions.map(\.exercise)); dismiss() }
                                catch { self.error = error.localizedDescription }
                            }
                        }.disabled(applying || suggestions.map(\.exercise.id) == exercises.map(\.id))
                        Text("这是基于训练重点的编排建议，不代表特定肌束顺序必然有更好的增肌效果。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Link("ACSM 训练建议依据", destination: URL(string: "https://doi.org/10.1249/MSS.0000000000003897")!)
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("训练顺序建议").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .task { do { catalog = try ExerciseCatalog.bundled() } catch { self.error = error.localizedDescription } }
        }
    }
}
