import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TrainingRecord.endedAt, order: .reverse) private var records: [TrainingRecord]
    @State private var error: String?
    var body: some View {
        List {
            Section { Text("记录保存在本机。运动匹配只关联你确认的健康记录，不会替你完成训练组。")
                    .font(.footnote).foregroundStyle(.secondary) }
            Section { NavigationLink("按动作查看重量与次数变化") { TrainingComparisonView() } }
            ForEach(records) { record in
                NavigationLink { RecordDetailView(record: record) } label: {
                    TrainingRecordRow(record: record)
                }
            }.onDelete { indices in
                for i in indices { context.delete(records[i]) }
                do { try context.save(); error = nil }
                catch { context.discardPendingChanges(); self.error = error.localizedDescription }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .overlay { if records.isEmpty { ContentUnavailableView("还没有训练记录", systemImage: "list.clipboard", description: Text("完成或提前结束训练后，记录会保存在这里。")) } }
        .navigationTitle("训练记录")
        .toolbar { EditButton() }
    }
}

struct RecordDetailView: View {
    @Environment(\.modelContext) private var context
    let record: TrainingRecord
    @State private var candidates: [WorkoutCandidate] = []
    @State private var selected: WorkoutCandidate?
    @State private var busy = false
    @State private var message: String?
    @State private var queryWindow: DateInterval?
    @State private var queryAt: Date?
    @State private var queryCount: Int?
    var body: some View {
        let performances = try? record.performances()
        let performedNames = record.performedNamesData.flatMap { try? JSONDecoder().decode([[String]].self, from: $0) }
        List {
            Section("训练概览") {
                Text(record.planName).font(.title2.bold())
                LabeledContent("状态", value: record.finished ? "已完成" : "提前结束")
                if let start = record.startedAt {
                    LabeledContent("开始", value: start.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("总时长", value: "\(max(0, Int(record.endedAt.timeIntervalSince(start) / 60))) 分钟")
                } else { Text("旧训练没有开始时间，无法进行时间匹配。") }
                LabeledContent("结束", value: record.endedAt.formatted(date: .abbreviated, time: .shortened))
            }
            Section("动作完成情况") {
                if let exercises = try? record.exercises(), let counts = try? record.completed(), counts.count == exercises.count {
                    ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                        VStack(alignment: .leading, spacing: 5) {
                            LabeledContent(exercise.name, value: "\(counts[index])/\(exercise.sets) 组")
                            if let performances, performances.indices.contains(index) {
                                ForEach(Array(performances[index].enumerated()), id: \.offset) { set, performance in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("第 \(set + 1) 组 · " + performance.exerciseName).font(.subheadline)
                                        Text(performance.values?.summary ?? "重量与次数未记录").font(.caption).foregroundStyle(.secondary)
                                        if let note = performance.values?.equipmentNote, !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                            } else if let names = performedNames, names.indices.contains(index) {
                                ForEach(Array(names[index].enumerated()), id: \.offset) { set, name in
                                    Text("第 \(set + 1) 组 · " + name + " · 重量与次数未记录").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else { Text("动作记录无法读取，请保留数据。").foregroundStyle(.red) }
            }
            if record.performancesData != nil && performances == nil {
                Section { Text("逐组重量记录暂时无法读取，请保留数据。").foregroundStyle(.red) }
            }
            Section {
                DisclosureGroup("Apple Watch／健康运动关联") {
                    Text("仅在你点击查询并授权后，读取健康App中已同步的运动。按时间重合排序，需手动确认；来源可能是手表或其他App，不会自动认定为Apple Watch。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let source = record.workoutSource {
                        Label("已关联：" + source, systemImage: "checkmark.circle.fill")
                        if let start = record.workoutStart, let end = record.workoutEnd {
                            Text("\(start.formatted(date: .abbreviated, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))")
                        }
                        Button("解除关联", role: .destructive) {
                            record.workoutID = nil; record.workoutSource = nil; record.workoutStart = nil; record.workoutEnd = nil
                            save()
                        }
                    }
                    if WorkoutReader.buildEnabled {
                        Button(busy ? "正在查询…" : "授权并查找时间相近的运动") { Task { await query() } }
                            .disabled(busy || record.startedAt == nil)
                    } else { Text(HealthFailure.buildDisabled.localizedDescription).font(.footnote) }
                    ForEach(candidates) { candidate in
                        Button { selected = candidate } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(candidate.title).font(.headline)
                                Text(candidate.source + (candidate.device.map { " · " + $0 } ?? ""))
                                Text("\(candidate.start.formatted(date: .abbreviated, time: .shortened)) – \(candidate.end.formatted(date: .omitted, time: .shortened))")
                                if let start = record.startedAt {
                                    Text("时间重合 \(Int(candidate.overlapScore(start: start, end: record.endedAt) * 100))% · 点击确认关联")
                                }
                            }.font(.caption)
                        }
                    }
                    if let queryWindow, let queryAt {
                        Text("最近查询：" + queryAt.formatted(date: .omitted, time: .standard)).font(.caption)
                        Text("时间窗口：" + queryWindow.start.formatted(date: .abbreviated, time: .shortened) + " – " + queryWindow.end.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                        if let queryCount { Text("返回 \(queryCount) 条候选；来源/设备按健康记录原值展示，不自动判定为Apple Watch。").font(.caption) }
                    }
                    if let message { Text(message).font(.footnote).textSelection(.enabled) }
                }
            }
        }
        .navigationTitle("训练详情")
        .confirmationDialog("关联这条运动记录？", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }), presenting: selected) { candidate in
            Button("确认关联") {
                record.workoutID = candidate.id.uuidString; record.workoutSource = candidate.source
                record.workoutStart = candidate.start; record.workoutEnd = candidate.end
                save(); self.selected = nil
            }
        } message: { _ in Text("仅按时间提供候选，重合不代表一定是同一次训练。不会修改健康App中的原始记录。") }
    }
    private func query() async {
        guard let start = record.startedAt else { return }
        busy = true; defer { busy = false }
        do {
            queryWindow = try WorkoutMatching.window(start: start, end: record.endedAt); queryAt = Date(); queryCount = nil
            candidates = try await WorkoutReader().candidates(start: start, end: record.endedAt)
            queryCount = candidates.count
            message = candidates.isEmpty ? "没有可读取的运动记录，也可能未授权、尚未同步或不在时间窗口内。" : nil
        } catch { message = error.localizedDescription }
    }
    private func save() {
        do { try context.save(); message = nil }
        catch { context.discardPendingChanges(); message = error.localizedDescription }
    }
}

private struct TrainingRecordRow: View {
    let record: TrainingRecord
    private var summary: String? {
        guard let counts = try? record.completed() else { return nil }
        var result = "完成 \(counts.reduce(0, +)) 组"
        if let start = record.startedAt {
            let minutes = max(0, Int(record.endedAt.timeIntervalSince(start) / 60))
            result += " · \(minutes) 分钟"
        }
        return result
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(record.planName).font(.headline)
                Spacer()
                Text(record.finished ? "已完成" : "提前结束").font(.caption).foregroundStyle(.secondary)
            }
            Text(record.endedAt, format: .dateTime.month().day().hour().minute()).font(.subheadline).foregroundStyle(.secondary)
            if let summary { Text(summary).font(.subheadline).monospacedDigit() }
            if let exercises = try? record.exercises() {
                Text(exercises.map(\.name).joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if let source = record.workoutSource { Label("已匹配 · " + source, systemImage: "heart.text.square").font(.caption).foregroundStyle(.orange) }
        }.padding(.vertical, 5)
    }
}
