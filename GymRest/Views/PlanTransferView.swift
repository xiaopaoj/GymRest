import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct PlanTransferView: View {
    private enum ImportMode: String, CaseIterable, Identifiable {
        case append, replaceProgram, replaceLibrary
        var id: Self { self }
        var title: String {
            switch self {
            case .append: "追加导入"
            case .replaceProgram: "覆盖所选计划"
            case .replaceLibrary: "覆盖全部计划"
            }
        }
    }
    private struct ImportReview: Identifiable {
        let id = UUID()
        let archive: PlanArchive
        let mode: ImportMode
        let targetID: UUID?
        let targetName: String
        let newProgramName: String
        let replacement: PlanArchive.ReplacementPreview?
    }
    @Environment(\.modelContext) private var context
    @Query(sort: \TrainingPlan.position) private var plans: [TrainingPlan]
    @Query(sort: \TrainingProgram.position) private var programs: [TrainingProgram]
    var targetProgram: TrainingProgram? = nil
    @State private var mode: ImportMode = .append
    @State private var chosenProgramID: UUID?
    @State private var initialized = false
    @State private var importName = "五分化"
    @State private var importing = false
    @State private var exporting = false
    @State private var document = PlanFile()
    @State private var review: ImportReview?
    @State private var stagedReview: ImportReview?
    @State private var reviewError: String?
    @State private var message: String?
    @State private var pasting = false
    @State private var pastedText = ""
    @State private var pasteError: String?
    var body: some View {
        Form {
            Section("导入方式") {
                Picker("方式", selection: $mode) {
                    ForEach(ImportMode.allCases) { Text($0.title).tag($0) }
                }
                Text(mode == .append ? "保留本地内容，作为副本追加。" : mode == .replaceProgram ? "替换所选计划内的全部训练日，其他计划保留。" : "替换全部本地计划和训练日，包含未归类内容。")
                    .font(.footnote).foregroundStyle(mode == .append ? Color.secondary : Color.orange)
            }
            Section("导入归属") {
                if mode == .replaceLibrary {
                    Text("新版文件按自带分组恢复，旧版文件归入下面的新建计划。")
                    TextField("旧格式上层计划名称", text: $importName)
                } else if let targetProgram {
                    LabeledContent(mode == .replaceProgram ? "覆盖目标" : "归入计划", value: targetProgram.name)
                } else {
                    Picker(mode == .replaceProgram ? "覆盖目标" : "旧格式训练日归入", selection: $chosenProgramID) {
                        Text(mode == .replaceProgram ? "请选择计划" : "新建计划").tag(UUID?.none)
                        ForEach(programs) { program in Text(program.name).tag(Optional(program.id)) }
                    }
                    if mode == .append && chosenProgramID == nil { TextField("上层计划名称", text: $importName) }
                }
                Text(mode == .replaceProgram ? "文件内所有训练日归入所选计划；目标内未在文件出现的旧训练日也会被移除。" : "旧版文件的plans是训练日；新版文件自带分组则保留其结构。从计划详情追加导入时归入该计划。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("计划备份") {
                Button("粘贴 JSON 文本") { pasteError = nil; pasting = true }
                Button { importing = true } label: { Label("导入 JSON 计划", systemImage: "square.and.arrow.down") }
                Button {
                    do { document = PlanFile(data: try PlanArchive.export(plans: plans, programs: programs)); exporting = true }
                    catch { message = error.localizedDescription }
                } label: { Label("导出全部计划", systemImage: "square.and.arrow.up") }
                Text("文件与粘贴导入均先预览再确认。训练记录、健康关联和当前训练快照保留；覆盖后计划采用文件内容。导出只包含计划，单次导入最大10MB。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let message { Section { Text(message).textSelection(.enabled) } }
        }
        .navigationTitle("导入与导出")
        .onAppear {
            guard !initialized else { return }; initialized = true
            let matching = programs.filter { $0.name == "五分化" }
            if matching.count == 1 { chosenProgramID = matching[0].id }
        }
        .sheet(isPresented: $pasting, onDismiss: {
            // Present review only after the paste sheet has actually closed.
            if let stagedReview { reviewError = nil; review = stagedReview; self.stagedReview = nil }
        }) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text("粘贴完整JSON，校验后预览\(mode.title)的范围，确认前不修改本地内容。")
                        .font(.footnote).foregroundStyle(.secondary)
                    TextEditor(text: $pastedText).font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    if let pasteError { Text(pasteError).foregroundStyle(.red) }
                }.padding()
                .navigationTitle("粘贴计划")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { stagedReview = nil; pasting = false } }
                    ToolbarItem(placement: .confirmationAction) { Button("校验并预览") {
                        do {
                            stagedReview = try prepareReview(PlanArchive.decode(Data(pastedText.utf8)))
                            pasting = false
                        } catch { pasteError = error.localizedDescription }
                    }.disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
            }
        }
        .sheet(item: $review) { value in
            NavigationStack {
                Form {
                    Section("本次导入") {
                        LabeledContent("方式", value: value.mode.title)
                        LabeledContent("目标", value: value.targetName)
                        LabeledContent("导入训练日", value: "\(value.archive.plans.count) 个")
                    }
                    Section("将导入的内容") {
                        if value.mode != .replaceProgram {
                            ForEach(value.archive.programs ?? [], id: \.id) { Text("计划：" + $0.name) }
                            if value.targetID == nil && value.archive.plans.contains(where: { $0.programID == nil }) {
                                LabeledContent("未分组训练日归入", value: value.newProgramName)
                            }
                        }
                        ForEach(value.archive.plans, id: \.id) { Text("训练日：" + $0.name) }
                    }
                    if let replacement = value.replacement {
                        Section("将被替换的本地内容") {
                            Text("\(replacement.programs.count) 套计划范围内的 \(replacement.days.count) 个训练日")
                            ForEach(replacement.programs, id: \.id) { Text("计划：" + $0.name) }
                            ForEach(replacement.days, id: \.id) { Text("训练日：" + $0.name) }
                            Text(value.mode == .replaceProgram ? "保留目标计划的名称；旧训练日全部移除，用文件中的训练日替换。文件内的分组会合并到目标计划。" : "以上计划及训练日会移除，再按文件内容创建。")
                                .foregroundStyle(.orange)
                        }
                    }
                    Section {
                        Text("训练记录、健康关联和当前训练快照保留。当前训练继续使用开始时的配置，导入内容用于之后新开的训练。")
                    }
                    if let reviewError {
                        Section {
                            Text(reviewError).foregroundStyle(.red)
                            Button("重新预览") {
                                do { review = try prepareReview(value.archive); self.reviewError = nil }
                                catch { self.reviewError = error.localizedDescription }
                            }
                        }
                    }
                }
                .navigationTitle("确认\(value.mode.title)")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { review = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(role: value.replacement == nil ? nil : .destructive) { apply(value) } label: {
                            Text(value.replacement == nil ? "确认追加" : "确认覆盖")
                        }.disabled(reviewError != nil)
                    }
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
                reviewError = nil; review = try prepareReview(PlanArchive.decode(Data(contentsOf: url)))
            } catch { message = "未导入：" + error.localizedDescription }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "GymRest-plans") { result in
            switch result {
            case .success: message = "计划已导出。"
            case .failure(let error): message = "未导出：" + error.localizedDescription
            }
        }
    }
    private func prepareReview(_ archive: PlanArchive) throws -> ImportReview {
        let selectedID = targetProgram?.id ?? chosenProgramID
        let replacement: PlanArchive.ReplacementPreview?
        let appendTarget: UUID?
        switch mode {
        case .append:
            replacement = nil
            appendTarget = targetProgram?.id ?? ((archive.programs ?? []).isEmpty ? chosenProgramID : nil)
        case .replaceProgram:
            guard let selectedID else { throw ArchiveFailure.invalid("请先选择要覆盖的本地计划。") }
            replacement = try archive.previewReplacement(in: context, scope: .program(selectedID))
            appendTarget = nil
        case .replaceLibrary:
            replacement = try archive.previewReplacement(in: context, scope: .library)
            appendTarget = nil
        }
        let targetName = replacement?.targetName ?? appendTarget.flatMap { id in programs.first { $0.id == id }?.name } ?? "按文件分组或新建计划"
        return ImportReview(archive: archive, mode: mode, targetID: appendTarget, targetName: targetName,
                            newProgramName: importName, replacement: replacement)
    }
    private func apply(_ value: ImportReview) {
        guard review?.id == value.id else { return }
        do {
            if let replacement = value.replacement {
                try value.archive.replace(in: context, confirmed: replacement, newProgramName: value.newProgramName)
            } else {
                let selected = value.targetID.flatMap { id in programs.first { $0.id == id } }
                if value.targetID != nil && selected == nil { throw ArchiveFailure.invalid("导入目标已不存在，请重新选择。") }
                try value.archive.append(to: context, targetProgram: selected, newProgramName: selected == nil ? value.newProgramName : nil)
            }
            message = "已完成\(value.mode.title)：\(value.archive.plans.count) 个训练日。"
            pastedText = ""; review = nil; reviewError = nil
        } catch { reviewError = error.localizedDescription }
    }
}
