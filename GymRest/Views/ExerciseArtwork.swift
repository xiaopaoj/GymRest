import SwiftUI
import UIKit

/// Original transparent PNGs on a dark canvas. Playback is an optional pose sequence,
/// not a claim of interpolated video or a timing source for the training session.
struct ExerciseArtwork: View {
    let item: CatalogExercise
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var images: [UIImage] = []
    @State private var selected = 0
    @State private var playing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !images.isEmpty {
                TimelineView(.periodic(from: .now, by: 0.8)) { timeline in
                    let sequence = [0, 1, 2, 1]
                    let step = Int(timeline.date.timeIntervalSinceReferenceDate / 0.8) % sequence.count
                    let index = playing && !reduceMotion ? sequence[step] : selected
                    Image(uiImage: images[min(index, images.count - 1)])
                        .resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 220)
                        .background(Color(red: 0.10, green: 0.14, blue: 0.18), in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel("\(item.name)，姿势示意第 \(min(index, images.count - 1) + 1) 帧")
                }
                HStack {
                    ForEach(images.indices, id: \.self) { index in
                        Button("姿势 \(index + 1)") { playing = false; selected = index }
                            .buttonStyle(.bordered)
                            .accessibilityAddTraits(selected == index && !playing ? .isSelected : [])
                    }
                    if !reduceMotion {
                        Button { playing.toggle() } label: {
                            Image(systemName: playing ? "pause.fill" : "play.fill")
                        }.buttonStyle(.bordered)
                            .accessibilityLabel(playing ? "暂停分帧播放" : "播放分帧示意")
                    }
                }
                Text("分帧姿势示意 · 可点选查看，动作范围与负荷请按自身能力调整。")
                    .font(.caption).foregroundStyle(.secondary)
            } else if item.media.approved, let asset = item.media.animationAsset, let url = Self.assetURL(asset) {
                LoopingExerciseDemo(url: url).frame(height: 220)
            } else {
                Text("当前动作暂无准确匹配的图片，可在动作库查看其他动作。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .task(id: item.id) {
            playing = false; selected = 0
            images = item.media.approved ? (item.media.frameAssets ?? []).compactMap { filename in
                Self.assetURL(filename).flatMap { UIImage(contentsOfFile: $0.path) }
            } : []
        }
        .onChange(of: reduceMotion) { _, enabled in if enabled { playing = false } }
        .onDisappear { playing = false }
    }
    static func assetURL(_ filename: String) -> URL? {
        guard filename == (filename as NSString).lastPathComponent, !filename.contains("..") else { return nil }
        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        return Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "ExerciseFrames")
    }
}

struct WorkoutGuideCreditsView: View {
    private let base = "https://github.com/bryllim/workout-guide"
    @State private var notices = ""
    var body: some View {
        List {
            Section("动作分帧素材 · CC BY-SA 4.0") {
                Text("作者：Bryl Lim。部分原始姿势来自 Everkinetic。PNG图像保持原样，仅为打包重命名，并可在App中按分帧顺序展示。")
                Link("Workout Guide 原项目", destination: URL(string: base)!)
                Link("Everkinetic 原始素材", destination: URL(string: "https://github.com/everkinetic/data")!)
                Link("CC BY-SA 4.0 完整许可", destination: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/legalcode")!)
                Link("固定版本与原始素材清单", destination: URL(string: base + "/blob/aac599224bb9780305239607ef98540b7e0ce389/packages/workout-guide/manifest.json")!)
                Text("复制或改编这些素材时，应保留作者、来源及许可，标明修改；改编素材继续采用相同许可。")
            }
            Section("逐帧作者、来源和校验值") {
                if let url = Bundle.main.url(forResource: "WorkoutGuideSources", withExtension: "json") {
                    ShareLink("导出完整素材来源记录", item: url)
                }
            }
            Section("随包许可与署名原文") {
                Text(notices).font(.caption).textSelection(.enabled)
            }
        }
        .navigationTitle("素材许可")
        .task {
            notices = ["WorkoutGuide-LICENSE", "WorkoutGuide-LICENSE-ASSETS", "WorkoutGuide-LICENSES", "WorkoutGuide-ATTRIBUTION"].compactMap { name in
                Bundle.main.url(forResource: name, withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            }.joined(separator: "\n\n")
        }
    }
}
