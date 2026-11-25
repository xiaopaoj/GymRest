import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct PlanTransferView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TrainingPlan.position) private var plans: [TrainingPlan]
    @State private var importing = false
    @State private var exporting = false
    @State private var document = PlanFile()
    @State private var pending: PlanArchive?
    @State private var message: String?
    @State private var pasting = false
    @State private var pastedText = ""
    @State private var pasteError: String?
    var body: some View {
        Form {
            Section("计划备份") {
                Button("粘贴 JSON 文本") { pasteError = nil; pasting = true }
                Button { importing = true } label: { Label("导入 JSON 计划", systemImage: "square.and.arrow.down") }
                Button {
                    do { document = PlanFile(data: try PlanArchive.export(plans: plans)); exporting = true }
                    catch { message = error.localizedDescription }
                } label: { Label("导出全部计划", systemImage: "square.and.arrow.up") }
                Text("导入会追加计划并生成新ID，保留原计划、当前训练和训练记录。导出只包含计划，不含健康数据或训练记录。单次导入最大10MB。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let message { Section { Text(message).textSelection(.enabled) } }
        }
        .navigationTitle("导入与导出")
        .sheet(isPresented: $pasting) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text("粘贴完整JSON。校验通过后追加到现有计划，不覆盖原内容。")
                        .font(.footnote).foregroundStyle(.secondary)
                    TextEditor(text: $pastedText).font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    if let pasteError { Text(pasteError).foregroundStyle(.red) }
                }.padding()
                .navigationTitle("粘贴计划")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { pasting = false } }
                    ToolbarItem(placement: .confirmationAction) { Button("校验并追加导入") {
                        do {
                            let archive = try PlanArchive.decode(Data(pastedText.utf8))
                            try archive.append(to: context)
                            message = "已追加导入 \(archive.plans.count) 套计划。"
                            pastedText = ""; pasting = false
                        } catch { pasteError = error.localizedDescription }
                    }.disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 10 * 1024 * 1024 else { throw ArchiveFailure.invalid("文件超过10MB。") }
                pending = try PlanArchive.decode(Data(contentsOf: url))
            } catch { message = "未导入：" + error.localizedDescription }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "GymRest-plans") { result in
            switch result {
            case .success: message = "计划已导出。"
            case .failure(let error): message = "未导出：" + error.localizedDescription
            }
        }
        .confirmationDialog("追加导入计划？", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("导入 \(pending?.plans.count ?? 0) 套计划") {
                guard let archive = pending else { return }; pending = nil
                do { try archive.append(to: context); message = "已追加导入 \(archive.plans.count) 套计划。" }
                catch { message = error.localizedDescription }
            }
        } message: { Text("文件已通过结构、名称、ID、组数及休息秒数校验。导入不覆盖现有内容。") }
    }
}
