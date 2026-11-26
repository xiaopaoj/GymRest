import SwiftUI

struct ImportMatchingView: View {
    @Environment(\.dismiss) private var dismiss
    @State var archive: PlanArchive
    let apply: (PlanArchive) throws -> Void
    @State private var catalog: ExerciseCatalog?
    @State private var choosing: ImportActionMatch?
    @State private var useCatalogName = true
    @State private var error: String?
    private func sourceSummary(_ row: ImportActionMatch) -> String {
        let exercise = archive.plans[row.day].exercises[row.exercise]
        if let index = row.alternative {
            let alternative = exercise.alternatives[index]
            return "文件设置：\(exercise.sets)组 / 休息\(alternative.restSeconds)秒 · " + (alternative.prescription?.summary ?? "负重未预设")
        }
        return "文件设置：\(exercise.sets)组 / 休息\(exercise.restSeconds)秒 · " + (exercise.prescription?.summary ?? "负重未预设")
    }
    var body: some View {
        List {
            if let catalog {
                let rows = ImportActionMatcher.rows(archive, catalog: catalog)
                Section {
                    Text("已关联 \(rows.filter { $0.kind == .identifier }.count) · 名称可匹配 \(rows.filter { $0.kind == .name }.count) · 未匹配 \(rows.filter { $0.kind == .unmatched }.count)")
                    Toggle("匹配时采用动作库名称", isOn: $useCatalogName)
                    Button("应用全部准确名称匹配") {
                        for row in rows where row.kind == .name { ImportActionMatcher.assign(row.target, row: row, archive: &archive, useCatalogName: useCatalogName) }
                    }
                    Text("仅接受唯一的完整名称或别名；相似名称不自动替换。手动匹配前请核对器材、握法和动作姿势。匹配保留原负重口径，器材变化时请另行调整。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(row.name).font(.headline)
                        Text(row.dayName + (row.alternative == nil ? " · 主动作" : " · 替代动作")).font(.caption)
                        Text(row.status).font(.caption).foregroundStyle(row.kind == .unmatched ? Color.orange : Color.secondary)
                        if let target = row.target {
                            Text("动作库：" + target.name).font(.subheadline)
                            Text(target.equipment.compactMap { ExerciseCatalog.equipmentNames[$0] }.joined(separator: " · ") + " · " + target.loadKind.title)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text(sourceSummary(row)).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("选择动作与查看图片") { choosing = row }
                            Spacer()
                            Button("保留自定义") { ImportActionMatcher.assign(nil, row: row, archive: &archive, useCatalogName: false) }
                        }.buttonStyle(.borderless)
                    }.padding(.vertical, 4)
                }
            } else { ProgressView("读取动作库…") }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
        }
        .navigationTitle("动作匹配")
        .toolbar { Button("应用到预览") {
            do { try apply(archive); dismiss() } catch { self.error = PlanImportSupport.message(error) }
        }.disabled(catalog == nil) }
        .sheet(item: $choosing) { row in
            NavigationStack {
                ExerciseCatalogView { item, _ in
                    ImportActionMatcher.assign(item, row: row, archive: &archive, useCatalogName: useCatalogName)
                    choosing = nil
                }.toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { choosing = nil } } }
            }
        }
        .task { do { catalog = try ExerciseCatalog.bundled() } catch { self.error = error.localizedDescription } }
    }
}
