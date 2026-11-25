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
            ForEach(records) { record in
                NavigationLink { RecordDetailView(record: record) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(record.planName).font(.headline)
                            Spacer()
                            Text(record.finished ? "已完成" : "提前结束").font(.caption).foregroundStyle(.secondary)
                        }
                        Text(record.endedAt, format: .dateTime.month().day().hour().minute()).font(.subheadline).foregroundStyle(.secondary)
                        if let counts = try? record.completed() { Text("完成 \(counts.reduce(0, +)) 组").font(.subheadline) }
                        if let source = record.workoutSource { Label("已匹配 · " + source, systemImage: "heart.text.square").font(.caption).foregroundStyle(.orange) }
                    }.padding(.vertical, 5)
                }
            }.onDelete { indices in
                for i in indices { context.delete(records[i]) }
                do { try context.save(); error = nil }
                catch { context.rollback(); self.error = error.localizedDescription }
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
    var body: some View {
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
                            if let data = record.performedNamesData,
                               let names = try? JSONDecoder().decode([[String]].self, from: data), names.indices.contains(index) {
                                ForEach(Array(names[index].enumerated()), id: \.offset) { set, name in
                                    Text("第 \(set + 1) 组 · " + name).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else { Text("动作记录无法读取，请保留数据。").foregroundStyle(.red) }
            }
            Section("匹配 Apple Watch / 健康运动") {
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
                if let message { Text(message).font(.footnote).textSelection(.enabled) }
            }
        }
        .navigationTitle("训练详情")
        .confirmationDialog("关联这条运动记录？", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            Button("确认关联") {
                guard let selected else { return }
                record.workoutID = selected.id.uuidString; record.workoutSource = selected.source
                record.workoutStart = selected.start; record.workoutEnd = selected.end
                save(); self.selected = nil
            }
        } message: { Text("仅按时间提供候选，重合不代表一定是同一次训练。不会修改健康App中的原始记录。") }
    }
    private func query() async {
        guard let start = record.startedAt else { return }
        busy = true; defer { busy = false }
        do {
            candidates = try await WorkoutReader().candidates(start: start, end: record.endedAt)
            message = candidates.isEmpty ? "没有可读取的运动记录，也可能未授权、尚未同步或不在时间窗口内。" : nil
        } catch { message = error.localizedDescription }
    }
    private func save() {
        do { try context.save(); message = nil }
        catch { context.rollback(); message = error.localizedDescription }
    }
}
