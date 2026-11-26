import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryBackupView: View {
    @Environment(\.modelContext) private var context
    @Bindable var controller: TrainingController
    @State private var document = PlanFile()
    @State private var exporting = false
    @State private var importing = false
    @State private var backup: LibraryBackup?
    @State private var restorePreferences = false
    @State private var confirming = false
    @State private var message: String?
    var body: some View {
        Form {
            Section("完整备份") {
                Text("保存全部计划、训练历史、逐组重量/次数、健康运动关联及设置。图片随App提供，无需重复备份。进行中的训练及系统提醒不在备份内。")
                    .font(.footnote)
                Button("导出完整备份") {
                    do {
                        document = PlanFile(data: try LibraryBackup.capture(context, preferences: controller.preferences).encoded())
                        exporting = true; message = nil
                    } catch { message = PlanImportSupport.message(error) }
                }
                Button("选择备份文件恢复") { importing = true }
            }
            if let backup {
                Section("恢复预览") {
                    LabeledContent("备份日期", value: backup.createdAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("计划 / 训练日", value: "\(backup.programs.count) / \(backup.days.count)")
                    LabeledContent("训练记录", value: "\(backup.records.count) 条")
                    Text("合并恢复：相同ID保留本地内容，仅补充缺失项；重复恢复不产生副本，不删除现有数据。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Toggle("同时恢复备份中的设置", isOn: $restorePreferences)
                    Button("确认合并恢复") { confirming = true }
                        .disabled(controller.session != nil || controller.recoveryIssue != nil)
                    if controller.session != nil || controller.recoveryIssue != nil { Text("请先结束或恢复当前训练。").foregroundStyle(.orange) }
                }
            }
            if let message { Section { Text(message).textSelection(.enabled) } }
        }
        .navigationTitle("备份与恢复")
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "GymRest-complete-backup") { result in
            switch result { case .success: message = "完整备份已导出。"; case .failure(let error): message = PlanImportSupport.message(error) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText, .data]) { result in
            do {
                let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 50 * 1024 * 1024 else { throw ArchiveFailure.invalid("备份文件不能超过50MB。") }
                backup = try LibraryBackup.decode(Data(contentsOf: url)); restorePreferences = false; message = nil
            } catch { backup = nil; message = PlanImportSupport.message(error) }
        }
        .confirmationDialog("合并恢复这份备份？", isPresented: $confirming) {
            Button("恢复缺失内容") {
                do {
                    guard let backup, controller.session == nil, controller.recoveryIssue == nil else { throw TrainingError.activeSession }
                    let result = try backup.merge(into: context, preferences: controller.preferences, restorePreferences: restorePreferences)
                    message = "已恢复 \(result.programs) 套计划、\(result.days) 个训练日、\(result.records) 条记录；保留 \(result.skipped) 项已有内容。"
                    self.backup = nil
                    Task { await controller.reconcile() }
                } catch { message = PlanImportSupport.message(error) }
            }
        } message: { Text("已有内容保留，确认前请核对备份日期。" + (restorePreferences ? "默认组数、休息和提醒设置将采用备份中的值。" : "当前设置保留。")) }
    }
}
