import SwiftUI
import UIKit

struct TrainingView: View {
    @Bindable var controller: TrainingController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var restClockSize: CGFloat = 72
    @ScaledMetric(relativeTo: .largeTitle) private var effortClockSize: CGFloat = 64
    private var controlLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
    }
    @State private var navigation: String?
    private struct AlternativeRequest: Identifiable {
        let id = UUID()
        let exercise: ExerciseSpec
        let interactionID: UUID?
    }
    @State private var choosingAlternative: AlternativeRequest?
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
    @AppStorage("trainingArtworkExpanded") private var showingArtwork = false
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
                            HealthActivityTip()
                            restControls(session)
                            effortContent(session)
                            measurementContent(session)
                            if !(session.originalExercises ?? session.exercises)[session.index].alternatives.isEmpty {
                                Button("切换替代动作", systemImage: "arrow.triangle.swap") { choosingAlternative = AlternativeRequest(exercise: (session.originalExercises ?? session.exercises)[session.index], interactionID: session.interactionID) }
                                    .disabled(session.phase != .training || session.sideProgress > 0 || session.effortTimer != nil)
                            }
                            artworkContent(session)
                            DisclosureGroup("动作安排与更多操作") {
                                VStack(alignment: .leading, spacing: 16) {
                                    exerciseProgress(session)
                                    navigationControls(session)
                                }.padding(.top, 8)
                            }
                        }.padding()
                    }
                }
                if let error = controller.error { Text(error).foregroundStyle(.red).textSelection(.enabled).padding() }
            }
            .safeAreaInset(edge: .bottom) {
                if let session = controller.session, session.phase != .completed { trainingActionBar(session) }
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
            .sheet(item: $choosingAlternative) { request in
                TrainingAlternativesView(exercise: request.exercise, catalog: catalog) { id in
                    guard controller.session?.interactionID == request.interactionID else { return false }
                    await controller.selectAlternative(id, interactionID: request.interactionID)
                    return controller.error == nil
                }
            }
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
        }
        ProgressView(value: Double(session.completedSets), total: Double(session.totalSets))
        Text("已完成 \(session.completedSets)/\(session.totalSets) 组 · 动作 \(session.index + 1)/\(session.exercises.count)")
            .font(.subheadline).foregroundStyle(.secondary)
        Text(session.current.name).font(.largeTitle.bold())
        Text(session.phase == .training ? "第 \(min(session.current.sets, session.completed[session.index] + 1)) / \(session.current.sets) 组 · " + session.partTitle : session.isTransitionRest ? "动作间休息" : "组间休息")
            .font(.title3.bold())
        if let catalog, let item = catalog.resolve(session.current) {
            NavigationLink { CatalogExerciseDetail(item: item, catalog: catalog) } label: {
                Label("动作要点、器材与演示", systemImage: "play.rectangle")
            }
        } else if let catalogIssue { Text(catalogIssue).font(.caption).foregroundStyle(.secondary) }
        else if catalog != nil { Text("尚未按名称匹配到动作图片，可从动作库选择具体动作。").font(.caption).foregroundStyle(.secondary) }
    }

    @ViewBuilder
    private func artworkContent(_ session: TrainingSession) -> some View {
        if let catalog, let item = catalog.resolve(session.current) {
            DisclosureGroup("查看动作图片 · " + item.name, isExpanded: $showingArtwork) {
                ExerciseArtwork(item: item, previewHeight: 150).id(item.id)
            }
        }
    }
    private func trainingActionBar(_ session: TrainingSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.phase == .training ? "正在训练 · " + session.partTitle : session.phase == .paused ? "休息已暂停" : session.isTransitionRest ? "动作间休息" : "组间休息")
                .font(.headline)
            if session.phase != .training {
                Text(session.isTransitionRest ? "接下来：" + session.nextName : "下一组：" + session.current.name)
                    .font(.caption).foregroundStyle(.secondary)
            }
            if session.phase == .training {
                if session.currentSetValues.durationSeconds != nil {
                    if let timer = session.effortTimer, timer.registered || timer.status != .running {
                        if timer.status == .paused {
                            Button { Task { await controller.resumeEffort() } } label: {
                                Text("继续计时 · " + session.partTitle).frame(maxWidth: .infinity, minHeight: 44)
                            }.buttonStyle(.borderedProminent)
                        } else {
                            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                                Button { Task { await controller.completeSet() } } label: {
                                    Text(session.completionTitle).frame(maxWidth: .infinity, minHeight: 44)
                                }.buttonStyle(.borderedProminent)
                                    .disabled(timer.status != .ready && timer.secondsLeft(at: timeline.date) > 0)
                            }
                            if timer.status == .running {
                                Button("暂停计时") { Task { await controller.pauseEffort() } }.buttonStyle(.bordered)
                            }
                        }
                    } else {
                        Button { Task { await controller.startEffort() } } label: {
                            Text(session.effortTimer == nil ? "开始计时 · " + session.partTitle : "重试计时提醒")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.borderedProminent)
                    }
                } else {
                    Button { Task { await controller.completeSet() } } label: {
                        Text(session.completionTitle + " · " + session.currentSetValues.summary)
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent)
                }
            } else {
                controlLayout {
                    Button(session.phase == .paused ? "继续休息" : "暂停休息") {
                        Task { if session.phase == .paused { await controller.resume() } else { await controller.pause() } }
                    }
                    Spacer()
                    Button("结束休息") { Task { await controller.skipRest() } }
                }.buttonStyle(.bordered)
            }
        }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity, alignment: .leading)
            .padding().background(.regularMaterial).disabled(controller.busy)
    }

    @ViewBuilder
    private func measurementContent(_ session: TrainingSession) -> some View {
        if session.completed[session.index] < session.current.sets {
            VStack(alignment: .leading, spacing: 10) {
                Text(session.phase == .training ? "本组训练设置" : "下一组训练设置").font(.headline)
                Text(session.currentSetValues.summary).font(.title3.monospacedDigit())
                if let origins = session.setValueOrigins, origins.indices.contains(session.index) { Text(origins[session.index]).font(.caption).foregroundStyle(.secondary) }
                if !session.currentSetValues.equipmentNote.isEmpty { Text(session.currentSetValues.equipmentNote).font(.caption) }
                if let previous = controller.previousSetValues {
                    Text("本次上一组：" + previous.summary).font(.caption).foregroundStyle(.secondary)
                }
                if session.sideProgress == 0 && session.effortTimer == nil { quickValues(session) }
                if controller.previousSetValues != nil && session.sideProgress == 0 && session.effortTimer == nil {
                    Button("沿用本动作上一组") { Task { await controller.reusePreviousSet(interactionID: session.interactionID) } }
                }
                Button("调整本组设置") { editingValues = ValuesRequest(values: session.currentSetValues, interactionID: session.interactionID) }
                    .disabled(session.sideProgress > 0 || session.effortTimer != nil)
                if session.sideProgress > 0 || session.effortTimer != nil { Text("当前组进行中，完成整组后可调整；计时可单独暂停或重置。").font(.caption).foregroundStyle(.secondary) }
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
                    .font(.system(size: restClockSize, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity).padding(.vertical)
            }
            Text(session.phase == .paused ? "休息已暂停 · 暂停期间不提醒" : session.reminderRegistered ? "系统休息提醒已注册" : "提醒尚未注册成功，请重试或跳过")
                .font(.subheadline).foregroundStyle(session.reminderRegistered || session.phase == .paused ? Color.secondary : Color.red)
            controlLayout {
                ForEach([-15, 15], id: \.self) { amount in
                    Button("\(amount > 0 ? "+" : "")\(amount)秒") { Task { await controller.adjust(by: amount) } }
                        .buttonStyle(.bordered).frame(maxWidth: .infinity)
                }
            }
            if session.isTransitionRest, let drafts = session.setDrafts, drafts.indices.contains(session.index + 1) {
                Text("下一动作预设：" + drafts[session.index + 1].summary).font(.subheadline)
            }
            Button("重新开始休息") { Task { await controller.restartRest() } }
        }
    }

    @ViewBuilder
    private func navigationControls(_ session: TrainingSession) -> some View {
        controlLayout {
            Button("上一个动作") { navigation = "previous" }.disabled(session.index == 0)
            Spacer()
            Button("跳过当前动作") { navigation = "skip" }
        }.padding(.top)
        Text("组数仅由你手动确认。时间调整只作用于本次休息。")
            .font(.footnote).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func effortContent(_ session: TrainingSession) -> some View {
        if session.phase == .training && (session.currentSetValues.durationSeconds != nil || session.currentSetValues.sideCount == 2) {
            VStack(alignment: .leading, spacing: 12) {
                Text(session.partTitle).font(.title2.bold())
                if session.currentSetValues.sideCount == 2 {
                    controlLayout {
                        Label("第1侧", systemImage: session.sideProgress > 0 ? "checkmark.circle.fill" : "circle")
                        Image(systemName: "arrow.right")
                        Label("第2侧", systemImage: "circle")
                    }.font(.headline).accessibilityElement(children: .combine)
                    Text(session.sideProgress == 0 ? "整组进度 0/2侧 · 左右先后自行决定" : "已完成第1侧 · 整组尚未完成，请换侧")
                        .font(.subheadline).foregroundStyle(.orange)
                }
                if let duration = session.currentSetValues.durationSeconds {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        let left = Int(ceil(session.effortTimer?.secondsLeft(at: timeline.date) ?? Double(duration)))
                        Text(String(format: "%02d:%02d", left / 60, left % 60))
                            .font(.system(size: effortClockSize, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                            .frame(maxWidth: .infinity)
                    }
                    if let timer = session.effortTimer {
                        Text(timer.status == .ready ? "计时结束，请确认完成" : timer.status == .paused ? "计时暂停 · 暂停期间不提醒" : timer.registered ? "动作计时提醒已注册 · 到时不自动计组" : "提醒未注册成功，请重试")
                            .font(.subheadline).foregroundStyle(timer.status == .running && !timer.registered ? Color.red : Color.secondary)
                        Button("重置当前侧计时") { Task { await controller.resetEffort() } }
                    } else { Text("准备好后开始计时，切换到其他App或锁屏后由系统提醒。").font(.footnote).foregroundStyle(.secondary) }
                }
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private func quickValues(_ session: TrainingSession) -> some View {
        let values = session.currentSetValues
        VStack(alignment: .leading, spacing: 8) {
            if let weight = values.weight, values.kind != .bodyweight {
                let step: Double = values.unit == .level ? 1 : 2.5
                quickAdjustment(title: "重量", value: "\(weight.formatted()) \(values.unit.title)", canDecrease: weight >= step, canIncrease: weight + step <= 10000) { delta in
                    var updated = values; updated.weight = weight + Double(delta) * step
                    Task { await controller.setValues(updated, interactionID: session.interactionID) }
                }
            }
            if let reps = values.repetitions {
                quickAdjustment(title: values.sideCount == 2 ? "每侧次数" : "次数", value: "\(reps) 次", canDecrease: reps > 1, canIncrease: reps < 1000) { delta in
                    var updated = values; updated.repetitions = reps + delta
                    Task { await controller.setValues(updated, interactionID: session.interactionID) }
                }
            }
        }
    }
    private func quickAdjustment(title: String, value: String, canDecrease: Bool, canIncrease: Bool, change: @escaping (Int) -> Void) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack { Text(title + " · " + value).monospacedDigit(); Spacer(); adjustmentButtons(title, canDecrease, canIncrease, change) }
            VStack(alignment: .leading) { Text(title + " · " + value).monospacedDigit(); adjustmentButtons(title, canDecrease, canIncrease, change) }
        }
    }
    private func adjustmentButtons(_ title: String, _ canDecrease: Bool, _ canIncrease: Bool, _ change: @escaping (Int) -> Void) -> some View {
        HStack {
            Button { change(-1) } label: { Image(systemName: "minus").frame(minWidth: 44, minHeight: 44) }
                .disabled(!canDecrease).accessibilityLabel("减少" + title)
            Button { change(1) } label: { Image(systemName: "plus").frame(minWidth: 44, minHeight: 44) }
                .disabled(!canIncrease).accessibilityLabel("增加" + title)
        }.buttonStyle(.bordered).disabled(controller.busy)
    }

    private func updateScreenAwake() {
        UIApplication.shared.isIdleTimerDisabled = controller.preferences.keepScreenOn && controller.session != nil && controller.session?.phase != .completed
    }
}
