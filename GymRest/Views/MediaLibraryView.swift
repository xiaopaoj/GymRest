import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let gymRestMedia = UTType(exportedAs: "dev.gymrest.media", conformingTo: .data)
}
struct MediaLibraryView: View {
    let controller: TrainingController
    @State private var media = MediaStore.shared
    @State private var importing = false
    @State private var prepared: PreparedMediaPack?
    @State private var error: String?
    @State private var exporting = false
    @State private var exported: URL?
    @State private var removing: String?
    @State private var allowDowngrade = false
    @State private var importBindings: [String: String] = [:]
    private var locked: Bool { controller.session != nil || controller.recoveryIssue != nil || media.busy || exporting }
    var body: some View {
        Form {
            Section("动作素材") {
                LabeledContent("IPA素材模式", value: Bundle.main.infoDictionary?["GymRestMediaMode"] as? String ?? "未知")
                LabeledContent("已有包策略", value: (Bundle.main.infoDictionary?["GymRestMediaSeedPolicy"] as? String) == "updateOfficial" ? "更新较新的官方包" : "保留本地")
                LabeledContent("已安装包", value: "\(media.selections.count)")
                LabeledContent("包内配图覆盖", value: "\(media.installedArtworkCount) 项")
                LabeledContent("活动版本资源", value: ByteCountFormatter.string(fromByteCount: Int64(media.installedBytes), countStyle: .file))
                Text("先导入一次，之后离线使用。App覆盖升级默认保留素材；卸载或清除数据后需重新导入。旧版本也占空间，移除整个包才删除其所有版本。")
                    .font(.footnote).foregroundStyle(.secondary)
                if let issue = media.issue { Text(issue).foregroundStyle(.red) }
                if controller.session != nil || controller.recoveryIssue != nil { Text("请先结束或恢复当前训练，再变更素材。").foregroundStyle(.orange) }
                Button("导入 .gymrestmedia 素材包") { importing = true }.disabled(locked)
                Text("首版请从与IPA一起发布的文件下载素材包；仅支持GymRest生成的未压缩ZIP格式。")
                    .font(.caption).foregroundStyle(.secondary)
                if media.busy { ProgressView("正在校验图片与来源…") }
            }
            ForEach(media.selections) { pack in
                Section(media.manifest(for: pack.id)?.title ?? pack.id) {
                    LabeledContent("版本", value: String(pack.revision))
                    Text(pack.id).font(.caption).textSelection(.enabled)
                    Toggle("使用此包", isOn: Binding(get: { media.selections.first { $0.id == pack.id }?.enabled ?? false }, set: { value in run { try media.setEnabled(pack.id, enabled: value) } })).disabled(locked)
                    Text("多个启用包包含同一动作时，后导入的包优先；更新同一包保持原优先级。")
                        .font(.caption).foregroundStyle(.secondary)
                    if let previous = pack.previous {
                        Button("切换到保留版本 \(previous)") { run { try media.rollback(pack.id) } }.disabled(locked)
                    }
                    Button("导出此素材包") {
                        exporting = true
                        Task {
                            defer { exporting = false }
                            do {
                                let directory = media.root.appendingPathComponent(pack.id).appendingPathComponent(String(pack.revision))
                                let bindings = pack.bindings ?? [:]
                                exported = try await Task.detached { try MediaPackExporter.export(directory: directory, bindings: bindings) }.value
                            } catch { self.error = error.localizedDescription }
                        }
                    }.disabled(locked)
                    Button("移除此包及保留版本", role: .destructive) { removing = pack.id }.disabled(locked)
                }
            }
            if let exported { Section { ShareLink("保存或分享已导出的素材包", item: exported) } }
            if let error { Section { Text(error).foregroundStyle(.red).textSelection(.enabled) } }
        }
        .navigationTitle("动作素材")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.gymRestMedia, .zip, .data]) { result in
            Task {
                do {
                    let value = try await media.prepare(url: result.get())
                    importBindings = media.selections.first { $0.id == value.manifest.packID }?.bindings ?? [:]
                    if let catalog = try? ExerciseCatalog.bundled() {
                        for entry in value.manifest.artwork where catalog.item(entry.catalogID) == nil && importBindings[entry.catalogID] == nil {
                            if let name = entry.name, let target = catalog.matching(name: name) { importBindings[entry.catalogID] = target.id }
                        }
                    }
                    prepared = value; allowDowngrade = false
                }
                catch { self.error = error.localizedDescription }
            }
        }
        .sheet(isPresented: Binding(get: { prepared != nil }, set: { if !$0 { discard() } })) {
            NavigationStack {
                if let value = prepared {
                    Form {
                        LabeledContent("包名", value: value.manifest.title)
                        LabeledContent("版本", value: String(value.manifest.revision))
                        let known = (try? ExerciseCatalog.bundled().exercises.map(\.id)) ?? []
                        let matched = value.manifest.artwork.filter { known.contains(importBindings[$0.catalogID] ?? $0.catalogID) }
                        LabeledContent("匹配动作 / 未匹配", value: "\(matched.count) / \(value.manifest.artwork.count - matched.count)")
                        LabeledContent("可配图动作", value: "\(matched.filter { $0.media.approved }.count)")
                        DisclosureGroup("核对未匹配或名称匹配的动作") {
                            let catalog = try? ExerciseCatalog.bundled()
                            ForEach(value.manifest.artwork.filter { !known.contains($0.catalogID) }, id: \.catalogID) { entry in
                                Picker(entry.name ?? entry.catalogID, selection: Binding(get: { importBindings[entry.catalogID] ?? "" }, set: { importBindings[entry.catalogID] = $0.isEmpty ? nil : $0 })) {
                                    Text("保持未匹配").tag("")
                                    ForEach(catalog?.exercises ?? []) { item in Text(item.name).tag(item.id) }
                                }.pickerStyle(.navigationLink)
                            }
                        }
                        LabeledContent("展开占用", value: ByteCountFormatter.string(fromByteCount: Int64(value.bytes), countStyle: .file))
                        if let old = media.selections.first(where: { $0.id == value.manifest.packID }) {
                            Text("只替换同一包 \(old.revision) → \(value.manifest.revision)，旧版保留供回滚；不改训练计划或记录。")
                            if value.manifest.revision < old.revision { Toggle("明确允许降级此包", isOn: $allowDowngrade) }
                        } else { Text("安装新包并启用；同动作优先于此前导入的包。未匹配动作保留在包内，不自动创建动作。") }
                        if let license = try? String(contentsOf: value.directory.appendingPathComponent("credits/LICENSE.txt"), encoding: .utf8) {
                            DisclosureGroup("许可与署名") { Text(license).font(.caption).textSelection(.enabled) }
                        }
                        if let error { Text(error).foregroundStyle(.red) }
                    }
                    .navigationTitle("素材导入预览")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("取消") { discard() } }
                        ToolbarItem(placement: .confirmationAction) { Button("安装") {
                            guard !locked else { error = "请结束当前训练后安装。"; return }
                            do { try media.install(value, allowDowngrade: allowDowngrade, bindings: importBindings); error = nil; discard() }
                            catch { self.error = error.localizedDescription }
                        } }
                    }
                }
            }.interactiveDismissDisabled(media.busy)
        }
        .confirmationDialog("移除此包及所有保留版本？", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("移除素材包", role: .destructive) {
                if let removing { run { try media.remove(removing) } }; removing = nil
            }
        } message: { Text("训练计划和记录保留；需要时可重新导入素材包。") }
        .onDisappear { if let exported { try? FileManager.default.removeItem(at: exported) } }
    }
    private func discard() { if let prepared { try? FileManager.default.removeItem(at: prepared.directory) }; prepared = nil }
    private func run(_ action: () throws -> Void) {
        guard !locked else { error = "当前不能变更素材，请结束训练后重试。"; return }
        do { try action(); error = nil } catch { self.error = error.localizedDescription }
    }
}
