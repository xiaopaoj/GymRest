import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TrainingPlan.position) private var plans: [TrainingPlan]
    @Bindable var controller: TrainingController
    @State private var creating = false
    @State private var newName = ""
    @State private var showTraining = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let session = controller.session {
                    Section {
                        Button { showTraining = true } label: {
                            Label("\(session.phase == .completed ? "训练已完成" : "继续训练") · \(session.planName)", systemImage: "play.circle.fill")
                                .font(.headline).padding(.vertical, 8)
                        }
                    }
                }
                Section("我的训练计划") {
                    ForEach(plans) { plan in
                        VStack(alignment: .leading, spacing: 12) {
                            NavigationLink { PlanEditor(plan: plan, controller: controller) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(plan.name).font(.title3.bold())
                                    if let exercises = try? plan.exercises() {
                                        Text("\(exercises.count) 个动作 · \(exercises.reduce(0) { $0 + $1.sets }) 组")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    } else { Text("动作数据读取失败，请勿覆盖").foregroundStyle(.red) }
                                }
                            }
                            Button {
                                Task {
                                    await controller.start(plan: plan)
                                    if controller.error == nil { showTraining = true }
                                }
                            } label: { Label("开始训练", systemImage: "play.fill").frame(maxWidth: .infinity) }
                                .buttonStyle(.borderedProminent).disabled(controller.busy || controller.session != nil && controller.session?.phase != .completed)
                        }.padding(.vertical, 8)
                            .swipeActions(edge: .leading) { Button("复制") { duplicate(plan) }.tint(.blue) }
                    }
                    .onDelete { indices in
                        for i in indices { context.delete(plans[i]) }
                        save()
                    }
                    .onMove { source, destination in
                        var ordered = plans; ordered.move(fromOffsets: source, toOffset: destination)
                        for (i, plan) in ordered.enumerated() { plan.position = i }
                        save()
                    }
                }
                Section { Text("计划中的每个动作单独设置组数和休息时间。滑动可复制，编辑模式可排序。")
                        .font(.footnote).foregroundStyle(.secondary) }
                if let error { Text(error).foregroundStyle(.red) }
                if let error = controller.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            }
            .navigationTitle("GymRest")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink { SettingsView(controller: controller) } label: { Image(systemName: "gearshape") }
                    Button { creating = true } label: { Image(systemName: "plus") }.accessibilityLabel("添加计划")
                }
            }
            .alert("新建训练计划", isPresented: $creating) {
                TextField("计划名称", text: $newName)
                Button("取消", role: .cancel) { newName = "" }
                Button("创建") { create() }
            }
            .fullScreenCover(isPresented: $showTraining) { TrainingView(controller: controller) }
        }
    }
    private func save() {
        do { try context.save(); error = nil }
        catch { context.rollback(); self.error = error.localizedDescription }
    }
    private func create() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 100 else { error = "计划名称须为1–100字。"; return }
        do {
            context.insert(try TrainingPlan(name: name, position: (plans.map(\.position).max() ?? -1) + 1))
            save(); newName = ""
        } catch { self.error = error.localizedDescription }
    }
    private func duplicate(_ plan: TrainingPlan) {
        do {
            var exercises = try plan.exercises()
            for i in exercises.indices { exercises[i].id = UUID() }
            context.insert(try TrainingPlan(name: String(plan.name.prefix(97)) + " 副本", position: (plans.map(\.position).max() ?? -1) + 1, exercises: exercises))
            save()
        } catch { error = error.localizedDescription }
    }
}
