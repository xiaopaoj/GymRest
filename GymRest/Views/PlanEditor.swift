import SwiftUI
import SwiftData

struct PlanEditor: View {
    @Environment(\.modelContext) private var context
    let plan: TrainingPlan
    let controller: TrainingController
    @State private var name = ""
    @State private var exercises: [ExerciseSpec] = []
    @State private var editing: ExerciseSpec?
    @State private var error: String?
    @State private var loaded = false
    var body: some View {
        List {
            Section("训练日名称") {
                TextField("名称", text: $name)
                Button("保存名称") {
                    let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty, value.count <= 100 else { error = "名称须为1–100字。"; return }
                    plan.name = value; save()
                }
            }
            Section("训练动作") {
                ForEach(exercises) { exercise in
                    Button { editing = exercise } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(exercise.name).foregroundStyle(.primary)
                                Text("\(exercise.sets) 组 · 休息 \(exercise.restSeconds) 秒")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }.padding(.vertical, 5)
                    }.swipeActions(edge: .leading) {
                        Button("复制") {
                            var copy = exercise; copy.id = UUID()
                            for i in copy.alternatives.indices { copy.alternatives[i].id = UUID() }
                            copy.name = String(copy.name.prefix(97)) + " 副本"
                            exercises.append(copy); saveExercises()
                        }.tint(.blue)
                    }
                }
                .onDelete { exercises.remove(atOffsets: $0); saveExercises() }
                .onMove { exercises.move(fromOffsets: $0, toOffset: $1); saveExercises() }
                Button { editing = ExerciseSpec(name: "", sets: controller.preferences.defaultSets, restSeconds: controller.preferences.defaultRest) } label: {
                    Label("添加动作", systemImage: "plus.circle.fill")
                }.disabled(!loaded)
            }
            Section { Text("拖拽调整执行顺序。训练开始后使用计划副本，此处修改将在下次训练生效。")
                    .font(.footnote).foregroundStyle(.secondary) }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("编辑训练日")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton().disabled(!loaded) } }
        .alert("保存未完成", isPresented: Binding(get: { error != nil && editing == nil }, set: { if !$0 { error = nil } })) {
            Button("知道了") { error = nil }
        } message: { Text(error ?? "") }
        .task {
            guard !loaded else { return }
            do {
                let values = try plan.exercises()
                for value in values { try value.validate() }
                exercises = values; name = plan.name; loaded = true
            }
            catch { self.error = error.localizedDescription }
        }
        .sheet(item: $editing) { exercise in
            ExerciseEditor(exercise: exercise) { value in
                var candidate = exercises
                if let i = candidate.firstIndex(where: { $0.id == value.id }) { candidate[i] = value }
                else { candidate.append(value) }
                try PlanEditing.save(candidate, to: plan, context: context)
                exercises = candidate; error = nil
            }
        }
    }
    private func save() {
        do { try context.save(); error = nil }
        catch { context.rollback(); self.error = error.localizedDescription }
    }
    private func saveExercises() {
        do {
            try PlanEditing.save(exercises, to: plan, context: context); error = nil
        } catch {
            context.rollback(); self.error = error.localizedDescription
            if let original = try? plan.exercises() { exercises = original }
        }
    }
}

struct ExerciseEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var exercise: ExerciseSpec
    @State private var seconds = ""
    @State private var editingAlternative: ExerciseAlternative?
    @State private var error: String?
    let onSave: (ExerciseSpec) throws -> Void
    private let presets = [30, 45, 60, 90, 120, 150, 180, 240, 300]
    var body: some View {
        NavigationStack {
            Form {
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section("训练动作") {
                    TextField("动作名称", text: $exercise.name)
                    Stepper("\(exercise.sets) 组", value: $exercise.sets, in: 1...100)
                }
                Section("独立休息时间") {
                    TextField("休息秒数", text: $seconds).keyboardType(.numberPad)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))]) {
                        ForEach(presets, id: \.self) { value in
                            Button("\(value) 秒") { seconds = String(value) }.buttonStyle(.bordered)
                        }
                    }
                    Toggle("最后一组后也休息", isOn: $exercise.restAfterLastSet)
                }
                Section("替代动作（可选）") {
                    ForEach(exercise.alternatives) { alternative in
                        Button { editingAlternative = alternative } label: {
                            LabeledContent(alternative.name, value: "\(alternative.restSeconds) 秒")
                        }
                    }.onDelete { exercise.alternatives.remove(atOffsets: $0) }
                    Button("添加替代动作") { editingAlternative = ExerciseAlternative(name: "", restSeconds: exercise.restSeconds) }
                    Text("替代动作共用本动作组数及末组休息开关，休息秒数独立。训练时可切换，已完成的组不会丢失。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    DisclosureGroup("按组覆盖休息（可选）") {
                        Text("未启用的组使用默认秒数。末组仍由“最后一组后也休息”开关决定是否计时。")
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(1...exercise.sets, id: \.self) { set in
                            Toggle("第 \(set) 组后", isOn: Binding(
                                get: { exercise.restOverrides[set] != nil },
                                set: { enabled in exercise.restOverrides[set] = enabled ? exercise.restSeconds : nil }))
                            if exercise.restOverrides[set] != nil {
                                TextField("秒数", value: Binding(
                                    get: { exercise.restOverrides[set] ?? exercise.restSeconds },
                                    set: { exercise.restOverrides[set] = $0 }), format: .number)
                                    .keyboardType(.numberPad)
                            }
                        }
                    }
                }
            }
            .onChange(of: exercise.sets) { _, count in exercise.restOverrides = exercise.restOverrides.filter { $0.key <= count }
                for i in exercise.alternatives.indices { exercise.alternatives[i].restOverrides = exercise.alternatives[i].restOverrides.filter { $0.key <= count } } }
            .navigationTitle(exercise.name.isEmpty ? "添加动作" : "编辑动作")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") {
                    exercise.name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    exercise.restSeconds = Int(seconds) ?? 0
                    do { try exercise.validate(); try onSave(exercise); dismiss() }
                    catch { self.error = error.localizedDescription }
                } }
            }
            .onAppear { if seconds.isEmpty { seconds = String(exercise.restSeconds) } }
            .alert("动作未保存", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("继续编辑") { error = nil }
            } message: { Text(error ?? "") }
            .sheet(item: $editingAlternative) { alternative in
                AlternativeEditor(alternative: alternative, sets: exercise.sets) { result in
                    if let i = exercise.alternatives.firstIndex(where: { $0.id == result.id }) { exercise.alternatives[i] = result }
                    else { exercise.alternatives.append(result) }
                }
            }
        }
    }
}

struct AlternativeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var alternative: ExerciseAlternative
    let sets: Int
    let save: (ExerciseAlternative) -> Void
    @State private var seconds = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("替代动作名称", text: $alternative.name)
                LabeledContent("共用训练组数", value: "\(sets) 组")
                TextField("独立休息秒数", text: $seconds).keyboardType(.numberPad)
                DisclosureGroup("按组覆盖休息（可选）") {
                    ForEach(1...sets, id: \.self) { set in
                        Toggle("第 \(set) 组后", isOn: Binding(get: { alternative.restOverrides[set] != nil }, set: { alternative.restOverrides[set] = $0 ? alternative.restSeconds : nil }))
                        if alternative.restOverrides[set] != nil {
                            TextField("秒数", value: Binding(get: { alternative.restOverrides[set] ?? alternative.restSeconds }, set: { alternative.restOverrides[set] = $0 }), format: .number).keyboardType(.numberPad)
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("替代动作")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") {
                    alternative.name = alternative.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    alternative.restSeconds = Int(seconds) ?? 0
                    do { try alternative.validate(sets: sets); save(alternative); dismiss() }
                    catch { self.error = error.localizedDescription }
                } }
            }.onAppear { seconds = String(alternative.restSeconds) }
        }
    }
}
