import SwiftUI
import SwiftData

struct LibraryView: View {
    @Bindable var controller: TrainingController
    @State private var tab = 0
    @State private var showingTraining = false
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { ProgramListView(controller: controller, showingTraining: $showingTraining).safeAreaInset(edge: .bottom, spacing: 0) { trainingReturnBar } }
                .tabItem { Label("计划", systemImage: "square.grid.2x2") }.tag(0)
            NavigationStack { ExerciseCatalogView().safeAreaInset(edge: .bottom, spacing: 0) { trainingReturnBar } }.tabItem { Label("动作", systemImage: "figure.strengthtraining.traditional") }.tag(3)
            NavigationStack { HistoryView().safeAreaInset(edge: .bottom, spacing: 0) { trainingReturnBar } }.tabItem { Label("记录", systemImage: "clock.arrow.circlepath") }.tag(1)
            NavigationStack { SettingsView(controller: controller).safeAreaInset(edge: .bottom, spacing: 0) { trainingReturnBar } }.tabItem { Label("设置", systemImage: "gearshape") }.tag(2)
        }
        .onChange(of: controller.session?.planID, initial: true) { _, id in
            if let id { UserDefaults.standard.set(id.uuidString, forKey: "lastTrainingDayID") }
        }
        .onOpenURL { url in
            if url.scheme == "gymrest", url.host == "training", controller.session != nil { showingTraining = true }
        }
        .fullScreenCover(isPresented: $showingTraining) { TrainingView(controller: controller) }
        .alert("操作未完成", isPresented: Binding(get: { !showingTraining && controller.error != nil }, set: { if !$0 && !showingTraining { controller.error = nil } })) {
            Button("知道了") { controller.error = nil }
        } message: { Text(controller.error ?? "请重试。") }
    }
    @ViewBuilder private var trainingReturnBar: some View {
        if let session = controller.session {
            CurrentTrainingBar(session: session) { showingTraining = true }
        }
    }

}

struct ProgramListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TrainingProgram.position) private var programs: [TrainingProgram]
    @Query(sort: \TrainingPlan.position) private var days: [TrainingPlan]
    let controller: TrainingController
    @Binding var showingTraining: Bool
    @AppStorage("lastTrainingDayID") private var lastTrainingDayID = ""
    @AppStorage("favoriteTrainingDayID") private var favoriteTrainingDayID = ""
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
            if controller.session == nil && !shortcutDays.isEmpty { shortcutSection }
            Section {
                NavigationLink { TrainingTemplateView() } label: {
                    Label("从三分化／五分化模板建立计划", systemImage: "sparkles.rectangle.stack")
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
                        ForEach(ungrouped) { day in
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
                    NavigationLink("训练模板") { TrainingTemplateView() }
                    NavigationLink("导入计划") { PlanTransferView() }
                } label: { Image(systemName: "plus") }.accessibilityLabel("添加或导入计划")
            }
        }
        .sheet(isPresented: $organizing) { NavigationStack { OrganizeProgramsView() } }
        .alert("保存失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("知道了") { error = nil }
        } message: { Text(error ?? "") }
    }
    private var shortcutDays: [TrainingPlan] {
        var result: [TrainingPlan] = []
        for id in [favoriteTrainingDayID, lastTrainingDayID] {
            if let day = days.first(where: { $0.id.uuidString == id }), !result.contains(where: { $0.id == day.id }) {
                result.append(day)
            }
        }
        return result
    }
    private var shortcutSection: some View {
        Section("快捷训练") {
            ForEach(shortcutDays) { day in
                NavigationLink { DayDetailView(day: day, controller: controller, showingTraining: $showingTraining) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(day.name, systemImage: day.id.uuidString == favoriteTrainingDayID ? "star.fill" : "arrow.counterclockwise")
                            .font(.headline)
                        Text(day.id.uuidString == favoriteTrainingDayID ? "常用训练 · 查看并开始" : "上次训练 · 再次训练")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
            }
        }
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
                if let target = program.weeklySessions { Text("每周目标 \(target) 次").font(.caption).foregroundStyle(.orange) }
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

private struct CurrentTrainingBar: View {
    let session: TrainingSession
    let open: () -> Void
    private var summary: String {
        switch session.phase {
        case .training: session.partTitle + " · 已完成 \(session.completedSets)/\(session.totalSets) 组"
        case .completed: session.planName
        case .paused: "休息已暂停"
        case .resting: session.isTransitionRest ? "动作间休息" : "组间休息"
        case .idle: "准备训练"
        }
    }
    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: session.phase == .completed ? "checkmark.circle.fill" : "figure.strengthtraining.traditional")
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.phase == .completed ? "查看训练结果" : session.current.name).font(.headline)
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.up")
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding()
                .contentShape(Rectangle())
        }.buttonStyle(.plain).background(.regularMaterial)
            .accessibilityHint("返回当前训练页面")
    }
}
