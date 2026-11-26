import Foundation
import Observation

@MainActor @Observable final class MediaStore {
    static let officialID = "org.gymrest.workout-guide"
    static let shared = MediaStore()
    struct Selection: Codable, Identifiable, Equatable {
        var id: String
        var revision: Int
        var previous: Int?
        var hash: String
        var enabled = true
        var bindings: [String: String]? = nil
        var previousBindings: [String: String]? = nil
    }
    struct Artwork {
        let media: CatalogMedia
        let frames: [URL]
        let fromPack: Bool
    }
    private(set) var selections: [Selection] = []
    private(set) var generation = UUID()
    private(set) var issue: String?
    private(set) var busy = false
    private var manifests: [String: MediaPackManifest] = [:]
    let root: URL
    private var bootstrapped = false
    private var indexBlocked = false
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MediaPacks")
        do {
            try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
            var url = self.root; var values = URLResourceValues(); values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            try? FileManager.default.removeItem(at: self.root.appendingPathComponent(".staging"))
            if FileManager.default.fileExists(atPath: self.root.appendingPathComponent("index.json").path) {
                let data = try Data(contentsOf: self.root.appendingPathComponent("index.json"))
                let loaded = try JSONDecoder().decode([Selection].self, from: data)
                guard Set(loaded.map(\.id)).count == loaded.count else { throw MediaPackFailure.invalid("本地索引重复。") }
                for item in loaded {
                    guard Self.validID(item.id), item.revision > 0, item.previous.map({ $0 > 0 }) ?? true else { throw MediaPackFailure.invalid("本地索引不合法。") }
                    let manifestData = try Data(contentsOf: directory(item.id, item.revision).appendingPathComponent("manifest.json"))
                    guard MediaArchive.hash(manifestData) == item.hash else { throw MediaPackFailure.invalid("本地索引与素材清单不一致。") }
                    let manifest = try JSONDecoder().decode(MediaPackManifest.self, from: manifestData)
                    guard manifest.packID == item.id, manifest.revision == item.revision else { throw MediaPackFailure.invalid("本地版本不一致。") }
                    try Self.validateFiles(manifest, directory: directory(item.id, item.revision))
                    manifests[item.id] = manifest
                }
                selections = loaded
            }
        } catch { issue = error.localizedDescription; indexBlocked = true }
    }
    private static func validID(_ id: String) -> Bool {
        id.first.map({ $0.isASCII && ($0.isLetter || $0.isNumber) }) == true && id.count <= 80 && id.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-").contains($0) } && !id.contains("..")
    }
    private func directory(_ id: String, _ revision: Int) -> URL { root.appendingPathComponent(id).appendingPathComponent(String(revision)) }
    private func save(_ values: [Selection]) throws {
        guard !indexBlocked else { throw MediaPackFailure.invalid("本地索引异常，请先保留素材目录并反馈，避免覆盖现有包。") }
        try JSONEncoder().encode(values).write(to: root.appendingPathComponent("index.json"), options: .atomic)
        selections = values; generation = UUID()
    }
    func manifest(for id: String) -> MediaPackManifest? { manifests[id] }
    var installedArtworkCount: Int {
        let known = Set((try? ExerciseCatalog.bundled().exercises.map(\.id)) ?? [])
        var mapped: [String: Bool] = [:]
        for pack in selections where pack.enabled {
            for entry in manifests[pack.id]?.artwork ?? [] {
                let id = pack.bindings?[entry.catalogID] ?? entry.catalogID
                if known.contains(id) { mapped[id] = entry.media.approved }
            }
        }
        return mapped.values.filter { $0 }.count
    }
    var installedBytes: Int { selections.reduce(0) { $0 + (manifests[$1.id]?.files.reduce(0, { $0 + $1.bytes }) ?? 0) } }
    func selection(for item: CatalogExercise) -> Artwork {
        _ = generation
        for pack in selections.reversed() where pack.enabled {
            if let entry = manifests[pack.id]?.artwork.first(where: { (pack.bindings?[$0.catalogID] ?? $0.catalogID) == item.id }) {
                let base = directory(pack.id, pack.revision).appendingPathComponent("frames")
                return Artwork(media: entry.media, frames: entry.media.approved ? (entry.media.frameAssets ?? []).compactMap { name in
                    let url = base.appendingPathComponent(name)
                    return name == (name as NSString).lastPathComponent && !name.contains("..") && FileManager.default.fileExists(atPath: url.path) ? url : nil
                } : [], fromPack: true)
            }
        }
        return Artwork(media: item.media, frames: item.media.approved ? (item.media.frameAssets ?? []).compactMap(Self.bundledAsset) : [], fromPack: false)
    }
    static func bundledAsset(_ filename: String) -> URL? {
        guard filename == (filename as NSString).lastPathComponent, !filename.contains("..") else { return nil }
        let name = (filename as NSString).deletingPathExtension, ext = (filename as NSString).pathExtension
        return Bundle.main.url(forResource: name, withExtension: ext) ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "ExerciseFrames")
    }
    func prepare(url: URL) async throws -> PreparedMediaPack {
        guard !busy else { throw MediaPackFailure.invalid("正在处理素材，请稍后。") }
        busy = true; defer { busy = false }
        let owned = url.startAccessingSecurityScopedResource(); defer { if owned { url.stopAccessingSecurityScopedResource() } }
        let data = try MediaArchive.read(url)
        let build = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
        let destination = root.appendingPathComponent(".staging").appendingPathComponent(UUID().uuidString)
        return try await Task.detached { try MediaArchive.prepare(data, build: build, destination: destination) }.value
    }
    func install(_ prepared: PreparedMediaPack, allowDowngrade: Bool = false, bindings: [String: String]? = nil) throws {
        guard !busy, !indexBlocked else { throw MediaPackFailure.invalid("素材状态忙或需要恢复。") }
        let manifest = prepared.manifest
        guard manifest.revision > 0, Self.validID(manifest.packID) else { throw MediaPackFailure.invalid("包标识不合法。") }
        if let bindings {
            let resolved = manifest.artwork.map { bindings[$0.catalogID] ?? $0.catalogID }
            guard Set(resolved).count == resolved.count else { throw MediaPackFailure.invalid("同包有多个条目匹配同一动作，请调整映射。") }
        }
        var values = selections
        let existing = values.firstIndex { $0.id == manifest.packID }
        if let existing {
            let old = values[existing]
            guard manifest.revision != old.revision || old.hash == prepared.manifestHash else { throw MediaPackFailure.invalid("同版本内容不同，拒绝覆盖。") }
            if manifest.revision == old.revision {
                if let bindings { values[existing].bindings = bindings; try save(values) }
                return
            }
            guard allowDowngrade || manifest.revision > old.revision else { throw MediaPackFailure.invalid("这是较旧版本，请明确选择降级后重试。") }
            values[existing] = Selection(id: manifest.packID, revision: manifest.revision, previous: old.revision, hash: prepared.manifestHash, enabled: old.enabled, bindings: bindings ?? old.bindings, previousBindings: old.bindings)
        } else { values.append(Selection(id: manifest.packID, revision: manifest.revision, previous: nil, hash: prepared.manifestHash, bindings: bindings)) }
        let target = directory(manifest.packID, manifest.revision)
        if FileManager.default.fileExists(atPath: target.path) {
            let oldData = try Data(contentsOf: target.appendingPathComponent("manifest.json"))
            guard MediaArchive.hash(oldData) == prepared.manifestHash else { throw MediaPackFailure.invalid("已保留的同版本内容不同。") }
            // Revalidated files replace an inactive leftover from an interrupted install.
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: prepared.directory, to: target)
        // If saving the index fails, the previous index and package remain active.
        try save(values)
        manifests[manifest.packID] = manifest; issue = nil
    }
    func setEnabled(_ id: String, enabled: Bool) throws {
        var values = selections
        guard let index = values.firstIndex(where: { $0.id == id }) else { return }
        if enabled, let manifest = manifests[id] { try Self.validateFiles(manifest, directory: directory(id, values[index].revision)) }
        values[index].enabled = enabled; try save(values)
    }
    func rollback(_ id: String) throws {
        var values = selections
        guard let index = values.firstIndex(where: { $0.id == id }), let previous = values[index].previous else { return }
        let data = try Data(contentsOf: directory(id, previous).appendingPathComponent("manifest.json"))
        let manifest = try JSONDecoder().decode(MediaPackManifest.self, from: data)
        guard manifest.packID == id, manifest.revision == previous else { throw MediaPackFailure.invalid("保留版本标识不一致。") }
        try Self.validateFiles(manifest, directory: directory(id, previous))
        let currentBindings = values[index].bindings
        values[index].bindings = values[index].previousBindings; values[index].previousBindings = currentBindings
        let current = values[index].revision
        values[index].revision = previous; values[index].previous = current; values[index].hash = MediaArchive.hash(data)
        try save(values); manifests[id] = manifest
    }
    func remove(_ id: String) throws {
        try save(selections.filter { $0.id != id }); manifests[id] = nil
        // Physical deletion after deactivation cannot leave the active index dangling.
        try FileManager.default.removeItem(at: root.appendingPathComponent(id))
    }
    func exportURL(_ id: String) throws -> URL {
        guard let item = selections.first(where: { $0.id == id }) else { throw MediaPackFailure.invalid("未安装此包。") }
        return try MediaPackExporter.export(directory: directory(id, item.revision), bindings: item.bindings ?? [:])
    }
    private static func validateFiles(_ manifest: MediaPackManifest, directory: URL) throws {
        for file in manifest.files {
            guard MediaArchive.validPath(file.path), file.bytes <= 10 * 1024 * 1024 else { throw MediaPackFailure.invalid("本地资源路径不合法。") }
            let data = try MediaArchive.read(directory.appendingPathComponent(file.path))
            guard data.count == file.bytes, MediaArchive.hash(data) == file.sha256 else { throw MediaPackFailure.invalid("本地资源损坏，请保留目录并重新导入素材。") }
        }
    }
    func bootstrap() async {
        guard !bootstrapped else { return }; bootstrapped = true
        guard !indexBlocked, let url = Bundle.main.url(forResource: "Official", withExtension: "gymrestmedia", subdirectory: "MediaResources") else { return }
        let policy = Bundle.main.infoDictionary?["GymRestMediaSeedPolicy"] as? String ?? "preserve"
        let existing = selections.first { $0.id == Self.officialID }
        if existing != nil && policy != "updateOfficial" { return }
        do {
            let prepared = try await prepare(url: url)
            defer { try? FileManager.default.removeItem(at: prepared.directory) }
            if let existing, prepared.manifest.revision <= existing.revision { return }
            try install(prepared)
        } catch { issue = "随包素材初始化未完成：" + error.localizedDescription }
    }
}
