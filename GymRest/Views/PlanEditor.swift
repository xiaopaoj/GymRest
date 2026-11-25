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
            Section("计划名称") {
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
                            var copy = exercise; copy.id = UUID(); copy.name = String(copy.name.prefix(97)) + " 副本"
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
        .navigationTitle("编辑计划")
        .toolbar { EditButton() }
        .task {
            guard !loaded else { return }
            do { exercises = try plan.exercises(); name = plan.name; loaded = true }
            catch { self.error = error.localizedDescription }
        }
        .sheet(item: $editing) { exercise in
            ExerciseEditor(exercise: exercise) { value in
                if let i = exercises.firstIndex(where: { $0.id == value.id }) { exercises[i] = value }
                else { exercises.append(value) }
                saveExercises()
            }
        }
    }
    private func save() {
        do { try context.save(); error = nil }
        catch { context.rollback(); self.error = error.localizedDescription }
    }
    private func saveExercises() {
        do {
            try plan.setExercises(exercises); try context.save(); error = nil
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
    @State private var error: String?
    let onSave: (ExerciseSpec) -> Void
    private let presets = [30, 45, 60, 90, 120, 150, 180, 240, 300]
    var body: some View {
        NavigationStack {
            Form {
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
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(exercise.name.isEmpty ? "添加动作" : "编辑动作")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") {
                    exercise.name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    exercise.restSeconds = Int(seconds) ?? 0
                    do { try exercise.validate(); onSave(exercise); dismiss() }
                    catch { self.error = error.localizedDescription }
                } }
            }.onAppear { seconds = String(exercise.restSeconds) }
        }
    }
}
