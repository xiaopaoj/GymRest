import SwiftUI
import UIKit

struct TrainingView: View {
    @Bindable var controller: TrainingController
    @Environment(\.dismiss) private var dismiss
    @State private var navigation: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                if let session = controller.session {
                    if session.phase == .completed {
                        VStack(spacing: 24) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 72)).foregroundStyle(.green)
                            Text("训练完成").font(.largeTitle.bold())
                            Text("\(session.planName) · 已完成 \(session.completedSets) 组")
                            Text("不保留历史训练记录").foregroundStyle(.secondary)
                            Button("返回计划") { Task { await controller.end(); if controller.error == nil { dismiss() } } }
                                .buttonStyle(.borderedProminent).controlSize(.large)
                        }.frame(maxWidth: .infinity).padding(.top, 80)
                    } else {
                        VStack(alignment: .leading, spacing: 24) {
                            Text(session.planName).font(.headline).foregroundStyle(.secondary)
                            ProgressView(value: Double(session.completedSets), total: Double(session.totalSets))
                            Text("已完成 \(session.completedSets)/\(session.totalSets) 组 · 动作 \(session.index + 1)/\(session.exercises.count)")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text(session.current.name).font(.largeTitle.bold())
                            Text("第 \(min(session.current.sets, session.completed[session.index] + (session.phase == .training ? 1 : 0))) / \(session.current.sets) 组")
                                .font(.title2)
                            Text("预设休息 \(session.current.restSeconds) 秒 · 下一动作：\(session.nextName)")
                                .foregroundStyle(.secondary)
                            if session.phase == .resting || session.phase == .paused {
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
                            HStack {
                                Button("上一个动作") { navigation = "previous" }.disabled(session.index == 0)
                                Spacer()
                                Button("跳过当前动作") { navigation = "skip" }
                            }.padding(.top)
                            Text("组数仅由你手动确认。时间调整只作用于本次休息。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }.padding()
                    }
                }
                if let error = controller.error { Text(error).foregroundStyle(.red).textSelection(.enabled).padding() }
            }
            .navigationTitle("当前训练").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("收起") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("结束", role: .destructive) { navigation = "end" } }
            }
            .disabled(controller.busy)
            .confirmationDialog("确认操作", isPresented: Binding(get: { navigation != nil }, set: { if !$0 { navigation = nil } })) {
                Button(navigation == "end" ? "提前结束训练" : navigation == "previous" ? "返回上一动作并重新计组" : "跳过当前动作", role: .destructive) {
                    let action = navigation; navigation = nil
                    Task {
                        if action == "end" { await controller.end(); if controller.error == nil { dismiss() } }
                        else { await controller.navigate(previous: action == "previous") }
                    }
                }
            } message: { Text("将取消当前系统提醒。跳过的组不会计为已完成；返回上一动作会清零该动作的完成组数。") }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = controller.preferences.keepScreenOn }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}
