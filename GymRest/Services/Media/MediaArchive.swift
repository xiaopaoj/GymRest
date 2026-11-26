import Foundation
import CryptoKit
import ImageIO

struct MediaPackManifest: Codable, Sendable {
    let format: String
    let schemaVersion: Int
    let packID: String
    let revision: Int
    let minimumAppBuild: Int
    let title: String
    let files: [File]
    let artwork: [Artwork]
    struct File: Codable, Sendable { let path: String; let bytes: Int; let sha256: String }
    struct Artwork: Codable, Sendable {
        let catalogID: String
        let media: CatalogMedia
        let name: String?
        enum CodingKeys: String, CodingKey { case catalogID, media, name }
        init(catalogID: String, media: CatalogMedia, name: String? = nil) { self.catalogID = catalogID; self.media = media; self.name = name }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            name = try values.decodeIfPresent(String.self, forKey: .name)
            media = try values.decode(CatalogMedia.self, forKey: .media)
            if let id = try values.decodeIfPresent(String.self, forKey: .catalogID), !id.isEmpty { catalogID = id }
            else if let name, !name.isEmpty { catalogID = "name:" + MediaArchive.hash(Data(name.utf8)) }
            else { throw MediaPackFailure.invalid("动作映射缺少标识和名称。") }
        }
    }
}
struct PreparedMediaPack: Sendable {
    let directory: URL
    let manifest: MediaPackManifest
    let manifestHash: String
    let bytes: Int
}
enum MediaPackFailure: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return "素材包：" + text }; return nil }
}

/// PNGs are already compressed. Version 1 deliberately accepts only ZIP_STORED,
/// without encryption, links, comments, ZIP64 or arbitrary extraction paths.
/// Nothing is extracted until both ZIP directories and the entire manifest validate.
enum MediaArchive {
    static let maxBytes = 100 * 1024 * 1024
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func validPath(_ path: String) -> Bool {
        let pieces = path.split(separator: "/", omittingEmptySubsequences: false)
        return !path.isEmpty && path.utf8.count <= 180 && !path.contains("\\") && !path.contains(":") &&
            pieces.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." && $0.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) } }
    }
    static func read(_ url: URL) throws -> Data {
        let value = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard value.isRegularFile == true, let size = value.fileSize, size <= maxBytes else { throw MediaPackFailure.invalid("文件须为不超过100MiB的普通文件。") }
        let data = try Data(contentsOf: url)
        guard data.count <= maxBytes else { throw MediaPackFailure.invalid("文件超过100MiB。") }
        return data
    }
    static func prepare(_ data: Data, build: Int, destination: URL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)) throws -> PreparedMediaPack {
        func reject(_ text: String) -> MediaPackFailure { .invalid(text) }
        guard data.count >= 22, data.count <= maxBytes else { throw reject("文件大小不合法。") }
        func number(_ offset: Int, _ length: Int) -> Int {
            guard offset >= 0, offset <= data.count - length else { return -1 }
            return (0..<length).reduce(0) { $0 | Int(data[offset + $1]) << ($1 * 8) }
        }
        func text(_ offset: Int, _ length: Int) throws -> String {
            guard offset >= 0, length >= 0, offset <= data.count - length,
                  let value = String(data: data.subdata(in: offset..<offset + length), encoding: .utf8), validPath(value) else { throw reject("归档路径不合法。") }
            return value
        }
        let footer = data.count - 22
        guard number(footer, 4) == 0x06054b50, number(footer + 4, 2) == 0, number(footer + 6, 2) == 0,
              number(footer + 8, 2) == number(footer + 10, 2), number(footer + 20, 2) == 0 else { throw reject("仅支持无注释、单卷的标准素材ZIP。") }
        let count = number(footer + 10, 2), directorySize = number(footer + 12, 4), directoryOffset = number(footer + 16, 4)
        guard (1...3000).contains(count), directoryOffset + directorySize == footer else { throw reject("文件数量或目录不合法。") }
        var position = directoryOffset
        var payloads: [String: Range<Int>] = [:]
        var spans: [Range<Int>] = []
        var total = 0
        for _ in 0..<count {
            guard number(position, 4) == 0x02014b50 else { throw reject("归档目录损坏。") }
            let flags = number(position + 8, 2), method = number(position + 10, 2)
            let size = number(position + 24, 4), compressed = number(position + 20, 4)
            let nameLength = number(position + 28, 2), extra = number(position + 30, 2), comment = number(position + 32, 2)
            let external = number(position + 38, 4), local = number(position + 42, 4)
            let path = try text(position + 46, nameLength)
            let fileType = (external >> 16) & 0xf000
            guard flags & ~0x0800 == 0, method == 0, size == compressed, size <= 10 * 1024 * 1024,
                  [0, 0x8000].contains(fileType), external & 0x10 == 0, extra == 0, comment == 0,
                  payloads[path] == nil, number(position + 34, 2) == 0,
                  number(local, 4) == 0x04034b50, number(local + 6, 2) == flags, number(local + 8, 2) == 0,
                  number(local + 14, 4) == number(position + 16, 4), number(local + 18, 4) == size, number(local + 22, 4) == size,
                  number(local + 26, 2) == nameLength, number(local + 28, 2) == 0,
                  (try text(local + 30, nameLength)) == path else { throw reject("不支持压缩/加密/链接或不一致的归档条目，请使用GymRest生成的素材包。") }
            let start = local + 30 + nameLength
            guard start + size <= directoryOffset else { throw reject("资源范围不合法。") }
            payloads[path] = start..<start + size; spans.append(local..<start + size)
            total += size
            guard total <= 200 * 1024 * 1024 else { throw reject("展开资源超过200MiB。") }
            position += 46 + nameLength
        }
        guard Set(payloads.keys.map { $0.precomposedStringWithCanonicalMapping.lowercased() }).count == count else { throw reject("资源路径存在大小写或Unicode别名冲突。") }
        guard position == footer else { throw reject("归档目录长度不一致。") }
        let sorted = spans.sorted { $0.lowerBound < $1.lowerBound }
        guard sorted.first?.lowerBound == 0, zip(sorted, sorted.dropFirst()).allSatisfy({ $0.0.upperBound == $0.1.lowerBound }), sorted.last?.upperBound == directoryOffset,
              let manifestRange = payloads["manifest.json"], manifestRange.count <= 2 * 1024 * 1024 else { throw reject("素材清单缺失或归档条目重叠。") }
        let manifestData = data.subdata(in: manifestRange)
        let manifest = try JSONDecoder().decode(MediaPackManifest.self, from: manifestData)
        guard manifest.format == "GymRestMedia", manifest.schemaVersion == 1, manifest.minimumAppBuild <= build,
              manifest.minimumAppBuild > 0, manifest.revision > 0, (1...80).contains(manifest.title.count),
              (1...80).contains(manifest.packID.count), !manifest.packID.contains(".."), manifest.packID.first.map({ $0.isASCII && ($0.isLetter || $0.isNumber) }) == true, manifest.packID.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-").contains($0) }),
              Set(manifest.files.map(\.path)).count == manifest.files.count,
              Set(manifest.artwork.map(\.catalogID)).count == manifest.artwork.count,
              !manifest.artwork.isEmpty, manifest.artwork.count <= 2000,
              Set(payloads.keys) == Set(manifest.files.map(\.path) + ["manifest.json"]) else { throw reject("素材清单不兼容或有重复/未登记资源。") }
        let fileNames = Set(manifest.files.map(\.path))
        guard fileNames.contains("credits/LICENSE.txt"), fileNames.contains("credits/Sources.json") else { throw reject("缺少许可或来源清单。") }
        for file in manifest.files {
            guard validPath(file.path), let range = payloads[file.path], file.bytes == range.count,
                  file.sha256.count == 64, hash(data.subdata(in: range)) == file.sha256,
                  (file.path.hasPrefix("frames/") && file.path.hasSuffix(".png")) || ["credits/LICENSE.txt", "credits/Sources.json", "credits/Review.json"].contains(file.path) else { throw reject("资源哈希、路径或大小不匹配。") }
            let bytes = data.subdata(in: range)
            if file.path.hasSuffix(".png") {
                guard let source = CGImageSourceCreateWithData(bytes as CFData, nil), CGImageSourceGetCount(source) == 1,
                      let type = CGImageSourceGetType(source), type as String == "public.png",
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
                      let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
                      let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
                      (1...4096).contains(width), (1...4096).contains(height),
                      CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { throw reject("图片损坏或尺寸超限。") }
            } else if file.path == "credits/LICENSE.txt" {
                guard let license = String(data: bytes, encoding: .utf8), !license.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw reject("许可为空。") }
            } else { _ = try JSONSerialization.jsonObject(with: bytes) }
        }
        for item in manifest.artwork {
            let media = item.media
            guard (1...100).contains(item.catalogID.count), item.name.map({ !$0.isEmpty && $0.count <= 100 }) ?? true, ["pending", "approved"].contains(media.status), media.animationAsset == nil, media.equipmentAsset == nil,
                  (media.frameAssets ?? []).count <= 3, Set(media.frameAssets ?? []).count == (media.frameAssets ?? []).count,
                  media.reviewNote.map({ $0.count <= 1000 }) ?? true,
                  media.allowsPlayback != true else { throw reject("动作配图映射不合法。") }
            if media.status == "approved" {
                guard media.approved, !(media.frameAssets ?? []).isEmpty else { throw reject("配图缺少署名、来源或图片。") }
            }
            for name in media.frameAssets ?? [] {
                guard name == (name as NSString).lastPathComponent, !name.contains(".."), fileNames.contains("frames/" + name) else { throw reject("配图引用不存在。") }
            }
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw reject("临时目录已经存在，请重新导入。") }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        do {
            for (path, range) in payloads {
                let url = destination.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.subdata(in: range).write(to: url)
            }
            return PreparedMediaPack(directory: destination, manifest: manifest, manifestHash: hash(manifestData), bytes: total)
        } catch { try? FileManager.default.removeItem(at: destination); throw error }
    }
}
