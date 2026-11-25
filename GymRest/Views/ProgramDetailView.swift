import SwiftUI
import SwiftData

struct ProgramDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TrainingPlan.position) private var allDays: [TrainingPlan]
    let program: TrainingProgram
    let controller: TrainingController
    @Binding var showingTraining: Bool
    @State private var creating = false
    @State private var renaming = false
    @State private var deleting = false
    @State private var name = ""
    @State private var showingBlanks = false
    @State private var error: String?
    private var days: [TrainingPlan] { allDays.filter { $0.programID == program.id } }
    private var populated: [TrainingPlan] { days.filter { (try? $0.exercises().isEmpty) != true } }
    private var blanks: [TrainingPlan] { days.filter { (try? $0.exercises().isEmpty) == true } }
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(program.name).font(.largeTitle.bold())
                    Text("\(days.count) 个训练日 · 按你的节奏选择当天训练")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 12)
            }
            Section("每周安排") {
                Toggle("设置每周目标", isOn: Binding(get: { program.weeklySessions != nil }, set: { enabled in
                    program.weeklySessions = enabled ? 3 : nil; save()
                }))
                if program.weeklySessions != nil {
                    Stepper("每周目标 \(program.weeklySessions ?? 3) 次", value: Binding(get: { program.weeklySessions ?? 3 }, set: { program.weeklySessions = $0; save() }), in: 1...7)
                }
                Text("按训练日循环，自行安排休息，不固定星期。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("选择训练日") {
                ForEach(Array(populated.enumerated()), id: \.element.id) { index, day in
                    NavigationLink { DayDetailView(day: day, controller: controller, showingTraining: $showingTraining) } label: { DayRow(day: day, index: index) }
                        .swipeActions(edge: .leading) { Button("复制") { duplicate(day) }.tint(.blue) }
                }
                .onDelete { indices in let selected = populated; for i in indices { context.delete(selected[i]) }; save() }
                .onMove { source, destination in
                    var ordered = populated; ordered.move(fromOffsets: source, toOffset: destination)
                    ordered.append(contentsOf: blanks)
                    for (i, day) in ordered.enumerated() { day.position = i }; save()
                }
                Button { name = ""; creating = true } label: { Label("添加训练日", systemImage: "plus.circle") }
            }
            if !blanks.isEmpty {
                Section {
                    DisclosureGroup("待配置训练日 · \(blanks.count)", isExpanded: $showingBlanks) {
                        ForEach(blanks) { day in
                            NavigationLink { DayDetailView(day: day, controller: controller, showingTraining: $showingTraining) } label: { DayRow(day: day, index: nil) }
                        }.onDelete { indices in let selected = blanks; for i in indices { context.delete(selected[i]) }; save() }
                    }
                }
            }
            Section {
                NavigationLink("整理已有训练到本计划") { OrganizeProgramsView(initialProgramID: program.id) }
                NavigationLink("导入训练日到本计划") { PlanTransferView(targetProgram: program) }
            }
        }
        .onAppear { if populated.isEmpty { showingBlanks = true } }
        .navigationTitle("计划详情").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                EditButton()
                Menu {
                    Button("复制整套计划") {
                        do { try ProgramLibrary.duplicate(program, context: context) }
                        catch { self.error = error.localizedDescription }
                    }
                    Button("重命名计划") { name = program.name; renaming = true }
                    Button("移除计划分组", role: .destructive) { deleting = true }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .alert("添加训练日", isPresented: $creating) {
            TextField("例如：周一｜胸 + 腹肌", text: $name)
            Button("取消", role: .cancel) {}
            Button("添加") { createDay() }
        }
        .alert("重命名计划", isPresented: $renaming) {
            TextField("计划名称", text: $name)
            Button("取消", role: .cancel) {}
            Button("保存") { if validName() { program.name = name.trimmingCharacters(in: .whitespacesAndNewlines); save() } }
        }
        .confirmationDialog("移除计划分组？", isPresented: $deleting) {
            Button("保留训练日并移除分组", role: .destructive) {
                do { try ProgramLibrary.detachAndDelete(program, context: context); dismiss() }
                catch { self.error = error.localizedDescription }
            }
        } message: { Text("训练日移到未归类区域，训练记录不会删除。") }
        .alert("操作未完成", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("知道了") { error = nil }
        } message: { Text(error ?? "") }
    }
    private func duplicate(_ source: TrainingPlan) {
        do {
            var exercises = try source.exercises()
            for i in exercises.indices {
                exercises[i].id = UUID()
                for j in exercises[i].alternatives.indices { exercises[i].alternatives[j].id = UUID() }
            }
            let copy = try TrainingPlan(name: String(source.name.prefix(97)) + " 副本", position: (days.map(\.position).max() ?? -1) + 1, exercises: exercises)
            copy.programID = program.id; context.insert(copy); try context.save()
        } catch { context.discardPendingChanges(); self.error = error.localizedDescription }
    }
    private func validName() -> Bool {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 100 else { error = "名称须为1–100字。"; return false }; return true
    }
    private func createDay() {
        guard validName() else { return }
        do {
            let day = try TrainingPlan(name: name.trimmingCharacters(in: .whitespacesAndNewlines), position: (days.map(\.position).max() ?? -1) + 1)
            day.programID = program.id; context.insert(day); save(); showingBlanks = true
        } catch { self.error = error.localizedDescription }
    }
    private func save() { do { try context.save() } catch { context.discardPendingChanges(); self.error = error.localizedDescription } }
}

struct DayDetailView: View {
    @Environment(\.modelContext) private var context
    let day: TrainingPlan
    let controller: TrainingController
    @Binding var showingTraining: Bool
    @State private var error: String?
    @State private var starting = false
    private var exercises: [ExerciseSpec]? { try? day.exercises() }
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(day.name).font(.title.bold())
                    if let exercises {
                        Label("\(exercises.count) 个动作 · \(exercises.reduce(0) { $0 + $1.sets }) 组", systemImage: "dumbbell")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 12)
            }
            Section("动作预览") {
                if let exercises {
                    ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.secondary).frame(width: 20)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(exercise.name).font(.headline)
                                Text("\(exercise.sets) 组 · 组间休息 \(exercise.restSeconds) 秒").font(.subheadline).foregroundStyle(.secondary)
                                let transition = exercise.transitionRestSeconds ?? (exercise.restAfterLastSet ? exercise.rest(afterSet: exercise.sets) : 0)
                                Text(transition > 0 ? "有下一动作时休息 \(transition) 秒" : "动作完成后直接切换")
                                    .font(.caption).foregroundStyle(.secondary)
                                if !exercise.alternatives.isEmpty {
                                    Text("可替换：" + exercise.alternatives.map(\.name).joined(separator: "、"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.padding(.vertical, 8)
                    }
                    if exercises.isEmpty { Text("先添加训练动作，再开始训练。").foregroundStyle(.secondary) }
                } else { Text("动作数据无法读取，不能开始训练。请保留数据并反馈。").foregroundStyle(.red) }
            }
        }
        .navigationTitle("训练日").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("编辑动作") { PlanEditor(plan: day, controller: controller) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if controller.recoveryIssue != nil {
                    Text("请先从计划首页恢复当前训练；历史记录与计划仍可查看。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if exercises?.isEmpty == false {
                    Button {
                        guard !starting else { return }; starting = true
                        Task {
                            defer { starting = false }
                            if let session = controller.session, session.phase != .completed {
                                if session.planID == day.id { showingTraining = true }
                                else { error = "已有未完成训练，请从首页继续或先结束它。" }
                                return
                            }
                            await controller.start(plan: day)
                            if controller.session?.planID == day.id && controller.session?.phase == .training && controller.error == nil { showingTraining = true }
                            else if controller.error == nil { error = "训练尚未启动，请稍后重试。" }
                        }
                    } label: {
                        HStack { if starting { ProgressView() }; Text(starting ? "正在开始…" : "开始训练").font(.headline) }
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }.buttonStyle(.borderedProminent).disabled(starting || controller.busy || controller.recoveryIssue != nil)
                } else if exercises != nil {
                    NavigationLink { PlanEditor(plan: day, controller: controller) } label: {
                        Label("添加训练动作", systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 12)
                    }.buttonStyle(.borderedProminent)
                }
            }.padding().background(.regularMaterial)
        }
        .alert("无法开始训练", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("知道了") { error = nil }
        } message: { Text(error ?? "") }
    }
}
