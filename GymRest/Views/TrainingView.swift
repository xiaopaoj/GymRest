import SwiftUI
import UIKit

struct TrainingView: View {
    @Bindable var controller: TrainingController
    @Environment(\.dismiss) private var dismiss
    @State private var navigation: String?
    @State private var choosingAlternative = false
    private struct ValuesRequest: Identifiable {
        let id = UUID()
        let values: SetValues
        let interactionID: UUID?
    }
    private struct OrderRequest: Identifiable {
        let id = UUID()
        let exercises: [ExerciseSpec]
        let interactionID: UUID?
    }
    @State private var editingValues: ValuesRequest?
    @State private var ordering: OrderRequest?
    @State private var catalog: ExerciseCatalog?
    @State private var catalogIssue: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                if let session = controller.session {
                    if session.phase == .completed {
                        completedContent(session)
                    } else {
                        VStack(alignment: .leading, spacing: 24) {
                            sessionHeader(session)
                            measurementContent(session)
                            exerciseProgress(session)
                            restControls(session)
                            navigationControls(session)
                        }.padding()
                    }
                }
                if let error = controller.error { Text(error).foregroundStyle(.red).textSelection(.enabled).padding() }
            }
            .sheet(item: $editingValues) { request in
                SetValuesEditor(values: request.values) { values in
                    await controller.setValues(values, interactionID: request.interactionID)
                    if let message = controller.error { throw NSError(domain: "GymRest.SetValues", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
                }
            }
            .sheet(item: $ordering) { request in
                TrainingOrderView(exercises: request.exercises) { values in
                    await controller.reorderRemaining(values.map(\.id), interactionID: request.interactionID)
                    if let message = controller.error { throw NSError(domain: "GymRest.Order", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
                }
            }
            .task {
                do { catalog = try ExerciseCatalog.bundled() }
                catch { catalogIssue = "动作资料暂无法读取，仍可继续训练。" }
            }
            .navigationTitle("当前训练").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("收起") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("结束", role: .destructive) { navigation = "end" } }
            }
            .disabled(controller.busy)
            .confirmationDialog("选择本组训练动作", isPresented: $choosingAlternative) {
                if let session = controller.session {
                    let original = (session.originalExercises ?? session.exercises)[session.index]
                    Button(original.name + "（原动作）") { Task { await controller.selectAlternative(nil) } }
                    ForEach(original.alternatives) { alternative in
                        Button(alternative.name + " · \(alternative.restSeconds)秒休息") { Task { await controller.selectAlternative(alternative.id) } }
                    }
                }
            } message: { Text("已完成组数和实际动作记录保留；接下来的组使用所选动作及其休息时间。") }
            .confirmationDialog("确认操作", isPresented: Binding(get: { navigation != nil }, set: { if !$0 { navigation = nil } }), presenting: navigation) { action in
                Button(action == "end" ? "提前结束训练" : action == "previous" ? "返回上一动作并重新计组" : "跳过当前动作", role: .destructive) {
                    navigation = nil
                    Task {
                        if action == "end" { await controller.end(); if controller.error == nil { dismiss() } }
                        else { await controller.navigate(previous: action == "previous") }
                    }
                }
            } message: { _ in Text("将取消当前系统提醒。跳过的组不会计为已完成；返回上一动作会清零该动作的完成组数。") }
            .alert("训练操作未完成", isPresented: Binding(get: { controller.error != nil }, set: { if !$0 { controller.error = nil } })) {
                Button("知道了") { controller.error = nil }
            } message: { Text(controller.error ?? "") }

        }
        .onAppear { updateScreenAwake() }
        .onChange(of: controller.session?.phase) { _, _ in updateScreenAwake() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
    @ViewBuilder
    private func completedContent(_ session: TrainingSession) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 72)).foregroundStyle(.green)
            Text("训练完成").font(.largeTitle.bold())
            Text("\(session.planName) · 已完成 \(session.completedSets) 组")
            Text(controller.error == nil ? "已保存到训练记录" : "记录保存遇到问题，请保留页面并重试").foregroundStyle(.secondary)
            Button("返回计划") { Task { await controller.end(); if controller.error == nil { dismiss() } } }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }.frame(maxWidth: .infinity).padding(.top, 80)
    }

    @ViewBuilder
    private func sessionHeader(_ session: TrainingSession) -> some View {
        Text(session.planName).font(.headline).foregroundStyle(.secondary)
        if let issue = controller.liveActivityIssue {
            Text(issue).font(.footnote).foregroundStyle(.secondary)
            Button("重试显示锁屏训练卡片") { Task { await controller.refreshLiveActivity() } }
        } else {
            Text("可在锁屏训练卡片或长按灵动岛后完成本组、控制休息。")
                .font(.footnote).foregroundStyle(.secondary)
        }
        ProgressView(value: Double(session.completedSets), total: Double(session.totalSets))
        Text("已完成 \(session.completedSets)/\(session.totalSets) 组 · 动作 \(session.index + 1)/\(session.exercises.count)")
            .font(.subheadline).foregroundStyle(.secondary)
        Text(session.current.name).font(.largeTitle.bold())
        if let catalog, let item = catalog.item(session.current.catalogID) {
            NavigationLink { CatalogExerciseDetail(item: item, catalog: catalog) } label: {
                Label("动作要点、器材与演示", systemImage: "play.rectangle")
            }
        } else if let catalogIssue { Text(catalogIssue).font(.caption).foregroundStyle(.secondary) }
    }

    @ViewBuilder
    private func measurementContent(_ session: TrainingSession) -> some View {
        if session.completed[session.index] < session.current.sets {
            VStack(alignment: .leading, spacing: 10) {
                Text(session.phase == .training ? "本组重量与次数" : "下一组重量与次数").font(.headline)
                Text(session.currentSetValues.summary).font(.title3.monospacedDigit())
                if !session.currentSetValues.equipmentNote.isEmpty { Text(session.currentSetValues.equipmentNote).font(.caption) }
                Button("调整本组设置") { editingValues = ValuesRequest(values: session.currentSetValues, interactionID: session.interactionID) }
                Text("预填值在完成本组时记录；未填写的值保持未记录。锁屏完成沿用这里的设置。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        }
        if session.phase == .training && controller.reorderableExercises.count > 1 {
            Button("剩余动作的顺序建议") { ordering = OrderRequest(exercises: controller.reorderableExercises, interactionID: session.interactionID) }
        }
        if let performed = session.performances?[session.index], !performed.isEmpty {
            DisclosureGroup("本动作已完成组 · \(performed.count)") {
                ForEach(Array(performed.enumerated()), id: \.offset) { index, set in
                    Text("第 \(index + 1) 组 · " + set.exerciseName + " · " + (set.values?.summary ?? "重量与次数未记录"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func exerciseProgress(_ session: TrainingSession) -> some View {
        if !(session.originalExercises ?? session.exercises)[session.index].alternatives.isEmpty {
            Button { choosingAlternative = true } label: { Label("器械被占用？切换替代动作", systemImage: "arrow.triangle.swap") }
                .disabled(session.phase != .training)
            if session.phase != .training { Text("休息结束或跳过后可切换。").font(.caption).foregroundStyle(.secondary) }
        }
        Text("第 \(min(session.current.sets, session.completed[session.index] + (session.phase == .training ? 1 : 0))) / \(session.current.sets) 组")
            .font(.title2)
        Text("组间休息 \(session.current.restSeconds) 秒 · 下一动作：\(session.nextName)")
            .foregroundStyle(.secondary)
        if session.phase == .training {
            if let duration = session.restDuration(afterSet: session.completed[session.index] + 1) {
                let isTransition = session.completed[session.index] + 1 == session.current.sets && session.index + 1 < session.exercises.count
                Text(isTransition ? "本动作完成后休息 \(duration) 秒，再进入下一动作" : "本组后休息 \(duration) 秒")
                    .font(.subheadline).foregroundStyle(.orange)
            } else {
                Text(session.index + 1 < session.exercises.count ? "本组后直接进入下一动作" : "本组完成后结束训练")
                    .font(.subheadline).foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func restControls(_ session: TrainingSession) -> some View {
        if session.phase == .resting || session.phase == .paused {
            if session.isTransitionRest {
                Text("动作间休息 · 下一动作：\(session.nextName)").font(.headline).foregroundStyle(.orange)
            }
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let left = Int(ceil(session.secondsLeft(at: timeline.date)))
                Text(String(format: "%02d:%02d", left / 60, left % 60))
                    .font(.system(size: 72, weight: .bold, design: .rounded)).monospacedDigit()
                    .frame(maxWidth: .infinity).padding(.vertical)
            }
            Text(session.phase == .paused ? "休息已暂停 · 暂停期间不提醒" : session.reminderRegistered ? "系统休息提醒已注册" : "提醒尚未注册成功，请重试或跳过")
                .font(.subheadline).foregroundStyle(session.reminderRegistered || session.phase == .paused ? Color.secondary : Color.red)
            HStack {
                ForEach([-30, -15, 15, 30], id: \.self) { amount in
                    Button("\(amount > 0 ? "+" : "")\(amount)s") { Task { await controller.adjust(by: amount) } }
                        .buttonStyle(.bordered).frame(maxWidth: .infinity)
                }
            }
            Button(session.phase == .paused ? "继续休息" : "暂停休息") {
                Task { if session.phase == .paused { await controller.resume() } else { await controller.pause() } }
            }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
            HStack {
                Button("重新开始休息") { Task { await controller.restartRest() } }
                Spacer()
                Button("跳过休息") { Task { await controller.skipRest() } }
            }
        } else {
            Label("准备好后完成一组，再开始休息", systemImage: "dumbbell.fill")
                .foregroundStyle(.secondary).padding(.vertical, 24)
            Button { Task { await controller.completeSet() } } label: {
                Text("完成本组").font(.title2.bold()).frame(maxWidth: .infinity).padding(.vertical, 20)
            }.buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private func navigationControls(_ session: TrainingSession) -> some View {
        HStack {
            Button("上一个动作") { navigation = "previous" }.disabled(session.index == 0)
            Spacer()
            Button("跳过当前动作") { navigation = "skip" }
        }.padding(.top)
        Text("组数仅由你手动确认。时间调整只作用于本次休息。")
            .font(.footnote).foregroundStyle(.secondary)
    }

    private func updateScreenAwake() {
        UIApplication.shared.isIdleTimerDisabled = controller.preferences.keepScreenOn && controller.session != nil && controller.session?.phase != .completed
    }
}
