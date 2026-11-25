import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Bindable var controller: TrainingController
    @State private var error: String?
    var body: some View {
        @Bindable var preferences = controller.preferences
        Form {
            Section("新动作默认值") {
                Stepper("默认 \(preferences.defaultSets) 组", value: $preferences.defaultSets, in: 1...100)
                Stepper("默认休息 \(preferences.defaultRest) 秒", value: $preferences.defaultRest, in: 1...86400, step: 15)
                Text("仅影响之后添加的动作，已有动作独立保存。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("提醒") {
                Toggle("使用本地通知降级", isOn: $preferences.notificationFallback).disabled(controller.session != nil)
                Text(preferences.notificationFallback ? "通知不保证突破静音或专注模式，不提供 AlarmKit 锁屏倒计时。" : "使用 AlarmKit 系统提醒，签名兼容性和系统行为仍待真机验证。")
                    .font(.footnote).foregroundStyle(.secondary)
                LabeledContent("权限状态", value: controller.permission)
                Button("申请当前提醒权限") { Task { await controller.authorize() } }.disabled(controller.busy)
                if controller.session == nil {
                    NavigationLink("系统提醒测试") { ProbeView() }
                } else { Text("结束当前训练后可进入独立提醒测试，避免互相取消计时。") }
            }
            Section("训练显示") { Toggle("训练页面保持屏幕常亮", isOn: $preferences.keepScreenOn) }
            Section("关于") {
                LabeledContent("版本", value: "0.2.0")
                Text("本地存储，无账号、无训练历史。")
            }
            if let error = error ?? controller.error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("设置")
        .onChange(of: preferences.defaultSets) { _, _ in save() }
        .onChange(of: preferences.defaultRest) { _, _ in save() }
        .onChange(of: preferences.notificationFallback) { _, _ in save(); Task { await controller.reconcile() } }
        .onChange(of: preferences.keepScreenOn) { _, _ in save() }
        .task { await controller.reconcile() }
    }
    private func save() {
        do { try context.save(); error = nil }
        catch { context.rollback(); self.error = error.localizedDescription }
    }
}
