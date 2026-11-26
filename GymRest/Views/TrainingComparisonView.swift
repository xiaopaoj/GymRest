import SwiftUI
import SwiftData

struct TrainingComparisonView: View {
    @Query(sort: \TrainingRecord.endedAt, order: .reverse) private var records: [TrainingRecord]
    @State private var search = ""
    var body: some View {
        let profiles = TrainingComparison.profiles(records).filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        List {
            Section {
                Text("按实际动作、单位、总重/单只/辅助重量口径及器械备注分别查看，不做跨器械换算或自动加重建议。仅展示有重量或次数的实际完成组，旧版未记录数据不推测。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(profiles) { profile in
                Section {
                    DisclosureGroup {
                        ForEach(profile.sessions.prefix(10)) { session in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(session.date, format: .dateTime.year().month().day().hour().minute()).font(.headline)
                                Text("已记录 \(session.values.count) 组").font(.caption)
                                ForEach(Array(session.values.enumerated()), id: \.offset) { index, values in
                                    Text("第 \(index + 1) 组 · " + values.summary).font(.subheadline)
                                }
                            }.padding(.vertical, 5)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(profile.name).font(.headline)
                            Text(profile.unit.title + " · " + profile.kind.title + (profile.equipmentNote.isEmpty ? "" : " · " + profile.equipmentNote))
                                .font(.caption).foregroundStyle(.secondary)
                            Text("\(profile.sessions.count) 次训练 · 展示最近10次").font(.caption)
                        }
                    }
                }
            }
            if profiles.isEmpty { ContentUnavailableView("暂无可对比的数据", systemImage: "chart.xyaxis.line", description: Text("训练时记录重量或次数，完成后可在这里逐次查看。")) }
        }
        .navigationTitle("动作训练对比")
        .searchable(text: $search, prompt: "搜索实际动作")
    }
}
