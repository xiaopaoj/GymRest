import SwiftUI
import SwiftData

struct LibraryView: View {
    @Bindable var controller: TrainingController
    @State private var tab = 0
    @State private var showingTraining = false
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { ProgramListView(controller: controller, showingTraining: $showingTraining) }
                .tabItem { Label("计划", systemImage: "square.grid.2x2") }.tag(0)
            NavigationStack { HistoryView() }.tabItem { Label("记录", systemImage: "clock.arrow.circlepath") }.tag(1)
            NavigationStack { SettingsView(controller: controller) }.tabItem { Label("设置", systemImage: "gearshape") }.tag(2)
        }
        .onOpenURL { url in
            if url.scheme == "gymrest", url.host == "training", controller.session != nil { showingTraining = true }
        }
        .fullScreenCover(isPresented: $showingTraining) { TrainingView(controller: controller) }
        .alert("操作未完成", isPresented: Binding(get: { !showingTraining && controller.error != nil }, set: { if !$0 && !showingTraining { controller.error = nil } })) {
            Button("知道了") { controller.error = nil }
        } message: { Text(controller.error ?? "请重试。") }
    }
}

struct ProgramListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TrainingProgram.position) private var programs: [TrainingProgram]
    @Query(sort: \TrainingPlan.position) private var days: [TrainingPlan]
    let controller: TrainingController
    @Binding var showingTraining: Bool
    @State private var organizing = false
    @State private var query = ""
    @State private var error: String?
    var body: some View {
        let overview = TrainingLibraryOverview(programs: programs, days: days)
        let primaryPrograms = programs.filter { !overview.templateIDs.contains($0.id) }
        let ungrouped = overview.unassigned
        List {
            if let issue = controller.recoveryIssue {
                Section("当前训练需恢复") {
                    Text(issue).font(.subheadline)
                    Button("重试恢复训练") { Task { await controller.retryRecovery() } }.disabled(controller.busy)
                }
            }
            if let session = controller.session {
                Section {
                    Button { showingTraining = true } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "play.circle.fill").font(.largeTitle)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(session.phase == .completed ? "查看训练结果" : "继续本次训练").font(.headline)
                                Text(session.planName).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer(); Image(systemName: "arrow.up.right")
                        }.padding(.vertical, 8)
                    }.buttonStyle(.plain).foregroundStyle(.orange)
                }
            }
            Section {
                ForEach(primaryPrograms.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { program in
                    NavigationLink {
                        ProgramDetailView(program: program, controller: controller, showingTraining: $showingTraining)
                    } label: { ProgramCard(program: program, days: (overview.grouped[program.id] ?? []).compactMap { overview.summaries[$0.id] }) }
                }
                .onMove { source, destination in
                    // Sorting is disabled while searching to preserve the full ordering.
                    var ordered = primaryPrograms; ordered.move(fromOffsets: source, toOffset: destination)
                    ordered.append(contentsOf: programs.filter { overview.templateIDs.contains($0.id) })
                    for (i, value) in ordered.enumerated() { value.position = i }; save()
                }.moveDisabled(!query.isEmpty)
            } header: {
                HStack { Text("我的计划"); Spacer(); Text("\(primaryPrograms.count) 套") }
            } footer: { Text("选择计划，再选择当天训练。空训练日进入后可添加动作。") }
            if !overview.templateIDs.isEmpty {
                Section {
                    DisclosureGroup("空白计划与模板") {
                        ForEach(programs.filter { overview.templateIDs.contains($0.id) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }) { program in
                            NavigationLink { ProgramDetailView(program: program, controller: controller, showingTraining: $showingTraining) } label: {
                                ProgramCard(program: program, days: (overview.grouped[program.id] ?? []).compactMap { overview.summaries[$0.id] })
                            }
                        }
                    }
                }
            }
            if !ungrouped.isEmpty {
                Section("整理旧版内容") {
                    Button { organizing = true } label: {
                        Label("将已有训练归入计划 · \(ungrouped.count) 项", systemImage: "folder.badge.plus")
                    }
                    DisclosureGroup("未归类训练") {
                        ForEach(ungrouped.filter { (try? $0.exercises().isEmpty) != true }) { day in
                            NavigationLink { DayDetailView(day: day, controller: controller, showingTraining: $showingTraining) } label: { DayRow(day: day, index: nil) }
                        }
                    }
                    DisclosureGroup("旧版空白项目") {
                        ForEach(ungrouped.filter { (try? $0.exercises().isEmpty) == true }) { day in
                            NavigationLink { DayDetailView(day: day, controller: controller, showingTraining: $showingTraining) } label: { DayRow(day: day, index: nil) }
                        }
                    }
                }
            }
            if programs.isEmpty && ungrouped.isEmpty {
                ContentUnavailableView("建立你的训练计划", systemImage: "square.grid.2x2", description: Text("例如创建“五分化”，再添加各训练日；也可以导入计划。"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("训练计划")
        .searchable(text: $query, prompt: "搜索计划")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton().disabled(programs.isEmpty || !query.isEmpty) }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("新建计划", systemImage: "folder.badge.plus") { organizing = true }
                    NavigationLink("导入计划") { PlanTransferView() }
                } label: { Image(systemName: "plus") }.accessibilityLabel("添加或导入计划")
            }
        }
        .sheet(isPresented: $organizing) { NavigationStack { OrganizeProgramsView() } }
        .alert("保存失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("知道了") { error = nil }
        } message: { Text(error ?? "") }
    }
    private func save() {
        do { try context.save() } catch { context.discardPendingChanges(); self.error = error.localizedDescription }
    }
}

private struct ProgramCard: View {
    let program: TrainingProgram
    let days: [TrainingDaySummary]
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.title2).foregroundStyle(.orange).padding(14)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 8) {
                Text(program.name).font(.title3.bold()).foregroundStyle(.primary)
                Text("\(days.count) 个训练日 · \(days.reduce(0) { $0 + ($1.exerciseCount ?? 0) }) 个动作")
                    .font(.subheadline).foregroundStyle(.secondary)
                if days.contains(where: { $0.exerciseCount == nil }) {
                    Text("部分训练日数据需检查").font(.caption).foregroundStyle(.red)
                }
                Text(days.prefix(3).map(\.name).joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }.padding(.vertical, 14)
    }
}

struct DayRow: View {
    let day: TrainingPlan
    let index: Int?
    var body: some View {
        HStack(spacing: 14) {
            if let index {
                Text(String(format: "%02d", index + 1)).font(.headline.monospacedDigit())
                    .foregroundStyle(.orange).frame(width: 38, height: 42)
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(day.name).font(.headline).foregroundStyle(.primary)
                if let exercises = try? day.exercises() {
                    Text(exercises.isEmpty ? "尚未添加动作" : "\(exercises.count) 个动作 · \(exercises.reduce(0) { $0 + $1.sets }) 组")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else { Text("数据无法读取，请保留内容").font(.caption).foregroundStyle(.red) }
            }
        }.padding(.vertical, 8)
    }
}
