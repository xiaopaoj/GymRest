import SwiftUI
import SwiftData
import ActivityKit

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Bindable var controller: TrainingController
    @State private var error: String?
    @State private var restDraft = ""
    private var versionDescription: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
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
                Text("开始训练后显示锁屏训练卡片，可完成本组、暂停或继续休息、加15秒及结束休息。长按灵动岛展开操作；系统可能要求先解锁。首次提醒授权请在App内完成。")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("需保留实时活动扩展并允许系统实时活动。通知降级也可使用训练卡片，但提醒仍受通知权限、静音和专注模式限制。")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("切换到其他App等待提醒时，点系统提醒的「结束休息」即可准备下一组，再锁屏做组。做完后从训练卡片点「完成本组」。仅锁屏不会计组。")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("申请当前提醒权限") { Task { await controller.authorize() } }.disabled(controller.busy)
                if controller.session == nil && controller.recoveryIssue == nil {
                    NavigationLink("系统提醒测试") { ProbeView() }
                } else { Text("当前训练结束或恢复正常后可进入独立提醒测试，避免互相取消计时。") }
            }
            Section("Watch开训提醒") {
                NavigationLink("Watch连接与记录") { WatchCompanionView() }
                Toggle("开始训练前提醒开启Watch训练", isOn: Binding(get: { preferences.watchStartReminder == true }, set: { preferences.watchStartReminder = $0 }))
                Text("每场新训练开始前手动确认一次；GymRest无法自动检测系统体能训练是否已开启。继续或恢复训练不重复提醒。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("训练显示") { Toggle("训练页面保持屏幕常亮", isOn: $preferences.keepScreenOn) }
            Section("计划与记录") {
                NavigationLink("计划 JSON 导入与导出") { PlanTransferView() }
                NavigationLink("完整备份与恢复") { LibraryBackupView(controller: controller) }
                NavigationLink("训练记录") { HistoryView() }
                Text(WorkoutReader.buildEnabled ? "已启用可选健康运动读取；GymRest Watch可单独授权记录，手机不重复写入训练。" : "当前为普通构建，不请求健康数据权限。HealthKit版本需要支持的签名能力。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("关于") {
                NavigationLink("Watch与锁屏真机验收") { DeviceVerificationView(controller: controller) }
                NavigationLink("动作素材管理") { MediaLibraryView(controller: controller) }
                NavigationLink("动作素材许可") { WorkoutGuideCreditsView() }
                LabeledContent("版本", value: versionDescription)
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
        .onChange(of: preferences.watchStartReminder) { _, _ in save() }
        .onChange(of: preferences.keepScreenOn) { _, _ in save() }
        .task { await controller.reconcile() }
    }
    private func save() {
        do { try context.save(); error = nil }
        catch { context.discardPendingChanges(); self.error = error.localizedDescription }
    }
}
