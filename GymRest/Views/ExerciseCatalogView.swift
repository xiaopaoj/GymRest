import SwiftUI
import AVKit
import UIKit

struct ExerciseCatalogView: View {
    var choose: ((CatalogExercise, ExerciseCatalog) -> Void)? = nil
    @State private var catalog: ExerciseCatalog?
    @State private var error: String?
    @State private var search = ""
    @State private var muscle = ""
    @State private var equipment = ""
    var body: some View {
        List {
            if let catalog {
                Section {
                    Picker("训练部位", selection: $muscle) {
                        Text("全部部位").tag("")
                        ForEach(MuscleGroup.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Picker("器材", selection: $equipment) {
                        Text("全部器材").tag("")
                        ForEach(ExerciseCatalog.equipmentNames.keys.sorted(), id: \.self) { Text(ExerciseCatalog.equipmentNames[$0]!).tag($0) }
                    }
                }
                Section("\(filtered(catalog).count) 个动作") {
                    ForEach(filtered(catalog)) { item in
                        NavigationLink { CatalogExerciseDetail(item: item, catalog: catalog, choose: choose) } label: {
                            CatalogExerciseRow(item: item)
                        }
                    }
                }
                Section { Text("肌群标注表示常见训练侧重，不代表完全孤立。缺少审核通过的素材时显示待补充，文字与动作数据离线可用。")
                        .font(.footnote).foregroundStyle(.secondary) }
            } else if let error {
                Text(error).foregroundStyle(.red)
                Button("重新载入") { load() }
            } else { ProgressView("载入动作目录…") }
        }
        .navigationTitle("动作库")
        .searchable(text: $search, prompt: "搜索中文或英文动作")
        .task { if catalog == nil { load() } }
    }
    private func filtered(_ catalog: ExerciseCatalog) -> [CatalogExercise] {
        catalog.exercises.filter { item in
            (muscle.isEmpty || item.primary.contains { MuscleGroup(rawValue: muscle)?.includes($0) == true }) &&
            (equipment.isEmpty || item.equipment.contains(equipment)) &&
            (search.isEmpty || item.name.localizedCaseInsensitiveContains(search) || item.englishName.localizedCaseInsensitiveContains(search))
        }
    }
    private func load() {
        do { catalog = try ExerciseCatalog.bundled(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
struct CatalogExerciseRow: View {
    let item: CatalogExercise
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "dumbbell.fill").foregroundStyle(.orange).frame(width: 42, height: 46)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(item.name).font(.headline).foregroundStyle(.primary)
                Text(item.primary.map(\.title).joined(separator: " / ")).font(.caption).foregroundStyle(.secondary)
                Text(item.equipment.compactMap { ExerciseCatalog.equipmentNames[$0] }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 5)
    }
}
struct CatalogExerciseDetail: View {
    let item: CatalogExercise
    let catalog: ExerciseCatalog
    var choose: ((CatalogExercise, ExerciseCatalog) -> Void)? = nil
    var body: some View {
        List {
            Section {
                CatalogExerciseRow(item: item)
                if item.media.approved, let asset = item.media.animationAsset,
                   let url = Self.localAsset(asset) {
                    LoopingExerciseDemo(url: url).frame(height: 210)
                } else {
                    ContentUnavailableView("动作演示待补充", systemImage: "figure.strengthtraining.traditional",
                        description: Text("暂未收录符合授权与统一风格要求的演示。"))
                }
            }
            Section("器材与肌群") {
                ForEach(item.equipment, id: \.self) { Text(ExerciseCatalog.equipmentNames[$0] ?? $0) }
                if item.media.approved, let asset = item.media.equipmentAsset, let url = Self.localAsset(asset),
                   let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 160)
                } else { Text("器材图片待补充").font(.caption).foregroundStyle(.secondary) }
                LabeledContent("主要肌群", value: item.primary.map(\.title).joined(separator: "、"))
                LabeledContent("辅助肌群", value: item.secondary.map(\.title).joined(separator: "、"))
            }
            Section("建议起点 · 可自行调整") {
                LabeledContent("组数 / 次数", value: "\(item.sets) 组 × \(item.repetitions) 次")
                LabeledContent("组间 / 动作间", value: "\(item.restSeconds) / \(item.transitionRestSeconds) 秒")
                Text("建议不含起始重量；根据动作完成质量选择负荷。单侧动作需完成两侧，次数按每侧记录。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("动作要点") { ForEach(item.cues, id: \.self) { Text($0) } }
            Section("替代选择 · 动作模式与主要部位相近") {
                if catalog.alternatives(to: item).isEmpty {
                    Text("当前目录暂无同模式替代项，可在动作库中查看该部位的其他动作。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(catalog.alternatives(to: item)) { alternative in
                    NavigationLink { CatalogExerciseDetail(item: alternative, catalog: catalog, choose: choose) } label: {
                        CatalogExerciseRow(item: alternative)
                    }
                }
                Text("器材、稳定性和活动范围可能不同；替换后独立设置重量，不直接沿用原动作负荷。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("资料来源") {
                Link("wger 动作参考", destination: URL(string: item.sourceURL)!)
                Text("作者：" + item.sourceAuthor).font(.caption)
                Link("数据许可", destination: URL(string: item.licenseURL)!)
                Text(catalog.attribution).font(.caption).foregroundStyle(.secondary)
                if item.media.approved {
                    Text("素材作者：" + (item.media.author ?? ""))
                    if let source = item.media.sourceURL, let url = URL(string: source) { Link("素材来源", destination: url) }
                    if let license = item.media.licenseURL, let url = URL(string: license) { Link("素材许可", destination: url) }
                }
            }
        }
        .navigationTitle(item.name).navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let choose {
                Button("选择此动作") { choose(item, catalog) }.buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity).padding().background(.regularMaterial)
            }
        }
    }
    private static func localAsset(_ filename: String) -> URL? {
        guard filename == (filename as NSString).lastPathComponent else { return nil }
        return Bundle.main.url(forResource: (filename as NSString).deletingPathExtension, withExtension: (filename as NSString).pathExtension)
    }
}
private struct LoopingExerciseDemo: View {
    let url: URL
    @State private var player = AVQueuePlayer()
    @State private var looper: AVPlayerLooper?
    var body: some View {
        VideoPlayer(player: player)
            .onAppear { player.isMuted = true; looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url)); player.play() }
            .onDisappear { player.pause(); looper = nil; player.removeAllItems() }
    }
}
