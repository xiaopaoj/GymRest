import SwiftUI
import SwiftData
import ActivityKit

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Bindable var controller: TrainingController
    @State private var error: String?
    @State private var restDraft = ""
    var body: some View {
        @Bindable var preferences = controller.preferences
        Form {
            Section("新动作默认值") {
                Stepper("默认 \(preferences.defaultSets) 组", value: $preferences.defaultSets, in: 1...100)
                HStack {
                    Text("默认休息秒数")
                    TextField("1–86400", text: $restDraft).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    Button("保存") {
                        guard let seconds = Int(restDraft), (1...86400).contains(seconds) else {
                            error = TimerFailure.invalidDuration.localizedDescription; return
                        }
                        preferences.defaultRest = seconds
                        restDraft = String(seconds)
                    }.disabled(restDraft == String(preferences.defaultRest))
                }
                Text("仅影响之后添加的动作，已有动作独立保存。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("提醒") {
                Toggle("使用本地通知降级", isOn: $preferences.notificationFallback).disabled(controller.session != nil || controller.recoveryIssue != nil)
                Text(preferences.notificationFallback ? "通知不保证突破静音或专注模式，不提供 AlarmKit 锁屏倒计时。" : "使用 AlarmKit 系统提醒，签名兼容性和系统行为仍待真机验证。")
                    .font(.footnote).foregroundStyle(.secondary)
                LabeledContent("权限状态", value: controller.permission)
                LabeledContent("系统实时活动", value: ActivityAuthorizationInfo().areActivitiesEnabled ? "允许" : "关闭")
                Text("AlarmKit休息计时支持锁屏和灵动岛显示；需支持的机型及正确保留扩展。实时活动开关允许不代表系统一定已展示。本地通知降级不提供此能力。")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("申请当前提醒权限") { Task { await controller.authorize() } }.disabled(controller.busy)
                if controller.session == nil && controller.recoveryIssue == nil {
                    NavigationLink("系统提醒测试") { ProbeView() }
                } else { Text("当前训练结束或恢复正常后可进入独立提醒测试，避免互相取消计时。") }
            }
            Section("训练显示") { Toggle("训练页面保持屏幕常亮", isOn: $preferences.keepScreenOn) }
            Section("计划与记录") {
                NavigationLink("计划 JSON 导入与导出") { PlanTransferView() }
                NavigationLink("训练记录") { HistoryView() }
                Text(WorkoutReader.buildEnabled ? "已启用可选健康运动读取；在记录详情中主动授权查询。" : "当前为普通构建，不请求健康数据权限。HealthKit版本需要支持的签名能力。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("关于") {
                LabeledContent("版本", value: "0.4.0")
                Text("训练计划与记录仅存本机，无账号和后端。")
            }
            if let error = error ?? controller.error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("设置")
        .onAppear { if restDraft.isEmpty { restDraft = String(preferences.defaultRest) } }
        .alert("设置未保存", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("继续编辑") { error = nil }
        } message: { Text(error ?? "") }
        .onChange(of: preferences.defaultSets) { _, _ in save() }
        .onChange(of: preferences.defaultRest) { _, _ in save() }
        .onChange(of: preferences.notificationFallback) { _, _ in save(); Task { await controller.reconcile() } }
        .onChange(of: preferences.keepScreenOn) { _, _ in save() }
        .task { await controller.reconcile() }
    }
    private func save() {
        do { try context.save(); error = nil }
        catch { context.discardPendingChanges(); self.error = error.localizedDescription }
    }
}
