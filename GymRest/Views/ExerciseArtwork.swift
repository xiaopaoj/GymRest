import SwiftUI
import UIKit
import ImageIO

/// Original transparent PNGs on a dark canvas. Playback is an optional pose sequence,
/// not a claim of interpolated video or a timing source for the training session.
struct ExerciseArtwork: View {
    let item: CatalogExercise
    var large = false
    var previewHeight: CGFloat = 220
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingLarge = false
    @State private var images: [UIImage] = []
    @State private var selected = 0
    @State private var playing = false

    private var artwork: MediaStore.Artwork { MediaStore.shared.selection(for: item) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !images.isEmpty {
                TimelineView(.periodic(from: .now, by: 0.8)) { timeline in
                    let sequence = images.count == 3 ? [0, 1, 2, 1] : Array(images.indices)
                    let step = Int(timeline.date.timeIntervalSinceReferenceDate / 0.8) % sequence.count
                    let index = playing && !reduceMotion && artwork.media.allowsPlayback == true ? sequence[step] : selected
                    Image(uiImage: images[min(index, images.count - 1)])
                        .resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: large ? 420 : previewHeight)
                        .background(artwork.media.lightBackground == true ? Color.white : Color(red: 0.10, green: 0.14, blue: 0.18), in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel("\(item.name)，姿势示意第 \(min(index, images.count - 1) + 1) 帧")
                }
                HStack {
                    ForEach(images.indices, id: \.self) { index in
                        Button("姿势 \(index + 1)") { playing = false; selected = index }
                            .buttonStyle(.bordered)
                            .accessibilityAddTraits(selected == index && !playing ? .isSelected : [])
                    }
                    if !reduceMotion && artwork.media.allowsPlayback == true && images.count > 1 {
                        Button { playing.toggle() } label: {
                            Image(systemName: playing ? "pause.fill" : "play.fill")
                        }.buttonStyle(.bordered)
                            .accessibilityLabel(playing ? "暂停分帧播放" : "播放分帧示意")
                    }
                }
                if !large { Button("放大查看图片") { showingLarge = true } }
                Text("静态姿势示意 · 编号不代表时间顺序；动作范围与负荷按自身能力调整。")
                    .font(.caption).foregroundStyle(.secondary)
            } else if artwork.media.approved, let asset = artwork.media.animationAsset, let url = Self.assetURL(asset) {
                LoopingExerciseDemo(url: url).frame(height: 220)
            } else {
                Text(artwork.media.approved ? "当前未加载到图片，请到设置 → 动作素材管理检查是否已导入并启用素材包。" : "当前动作暂无准确匹配的图片，可在动作库查看其他动作。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if artwork.fromPack, let author = artwork.media.author, let license = artwork.media.licenseURL, let url = URL(string: license) {
                Link("素材：" + author + " · 许可", destination: url).font(.caption)
            }
            if let note = artwork.media.reviewNote { Text(note).font(.caption).foregroundStyle(.secondary) }
        }
        .sheet(isPresented: $showingLarge) {
            NavigationStack {
                ScrollView { ExerciseArtwork(item: item, large: true).padding() }
                    .navigationTitle(item.name).navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("关闭") { showingLarge = false } }
            }
        }
        .task(id: item.id + MediaStore.shared.generation.uuidString) {
            playing = false; selected = 0
            images = artwork.frames.compactMap { UIImage(contentsOfFile: $0.path) }
        }
        .onChange(of: reduceMotion) { _, enabled in if enabled { playing = false } }
        .onDisappear { playing = false }
    }
    static func assetURL(_ filename: String) -> URL? {
        MediaStore.bundledAsset(filename)
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
            ForEach(MediaStore.shared.selections) { pack in
                Section("已安装包 · " + pack.id) {
                    let directory = MediaStore.shared.root.appendingPathComponent(pack.id).appendingPathComponent(String(pack.revision)).appendingPathComponent("credits")
                    ShareLink("导出当前包来源", item: directory.appendingPathComponent("Sources.json"))
                    ShareLink("导出当前包许可", item: directory.appendingPathComponent("LICENSE.txt"))
                }
            }
            Section("逐帧作者、来源和校验值") {
                if let url = Bundle.main.url(forResource: "WorkoutGuideSources", withExtension: "json") {
                    ShareLink("导出Workout Guide逐帧来源", item: url)
                }
            }
            if let url = Bundle.main.url(forResource: "EverkineticSources", withExtension: "json") { Section { ShareLink("导出Everkinetic补充素材来源", item: url) } }
            if let url = Bundle.main.url(forResource: "WorkoutGuideMediaReview", withExtension: "json") { Section { ShareLink("导出分帧核对记录", item: url) } }
            Section("随包许可与署名原文") {
                Text(notices).font(.caption).textSelection(.enabled)
            }
        }
        .navigationTitle("素材许可")
        .task {
            notices = ["WorkoutGuide-LICENSE", "WorkoutGuide-LICENSE-ASSETS", "WorkoutGuide-LICENSES", "WorkoutGuide-ATTRIBUTION", "Everkinetic-LICENSE"].compactMap { name in
                Bundle.main.url(forResource: name, withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            }.joined(separator: "\n\n")
        }
    }
}

/// Load one downsampled pose per visible row to avoid decoding full sequences in lists.
struct ExerciseThumbnail: View {
    let item: CatalogExercise
    @State private var thumbnail: UIImage?
    @State private var lightBackground = false
    var body: some View {
        Group {
            if let thumbnail { Image(uiImage: thumbnail).resizable().scaledToFit() }
            else { Image(systemName: "figure.strengthtraining.traditional").foregroundStyle(.secondary) }
        }.frame(width: 56, height: 56)
            .background(lightBackground ? Color.white : Color(red: 0.10, green: 0.14, blue: 0.18), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
            .task(id: item.id + MediaStore.shared.generation.uuidString) {
                thumbnail = nil
                let selection = MediaStore.shared.selection(for: item)
                lightBackground = selection.media.lightBackground == true
                if let url = selection.frames.first,
                   let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                   let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 168,
                    kCGImageSourceCreateThumbnailWithTransform: true
                   ] as CFDictionary) {
                    thumbnail = UIImage(cgImage: image)
                }
            }
    }
}
