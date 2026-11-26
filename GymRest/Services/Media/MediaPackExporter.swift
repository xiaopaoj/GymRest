import Foundation

/// Minimal ZIP_STORED writer matching the bounded version-1 importer.
enum MediaPackExporter {
    private static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 { crc = crc & 1 == 0 ? crc >> 1 : 0xedb88320 ^ (crc >> 1) }
        return crc
    }
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8) }
        return crc ^ 0xffffffff
    }
    static func export(directory: URL, bindings: [String: String] = [:]) throws -> URL {
        var manifestData = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        var manifest = try JSONDecoder().decode(MediaPackManifest.self, from: manifestData)
        var replacements: [String: Data] = [:]
        if !bindings.isEmpty {
            let resolved = manifest.artwork.map { bindings[$0.catalogID] ?? $0.catalogID }
            guard Set(resolved).count == resolved.count else { throw MediaPackFailure.invalid("本地映射重复，无法导出。") }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let bindingData = try encoder.encode(bindings)
            let originalID = manifest.packID
            let derivedID = "user.mapped-" + String(MediaArchive.hash(manifestData + bindingData).prefix(24))
            let source = try Data(contentsOf: directory.appendingPathComponent("credits/Sources.json"))
            let sourceObject = try JSONSerialization.jsonObject(with: source)
            let annotated = try JSONSerialization.data(withJSONObject: ["original": sourceObject, "localMapping": bindings, "originalPackID": originalID], options: [.sortedKeys])
            replacements["credits/Sources.json"] = annotated
            let files = manifest.files.map { file in
                replacements[file.path].map { MediaPackManifest.File(path: file.path, bytes: $0.count, sha256: MediaArchive.hash($0)) } ?? file
            }
            manifest = MediaPackManifest(format: manifest.format, schemaVersion: manifest.schemaVersion, packID: String(derivedID), revision: manifest.revision,
                minimumAppBuild: manifest.minimumAppBuild, title: String(("本地匹配 · " + manifest.title).prefix(80)), files: files,
                artwork: manifest.artwork.map { .init(catalogID: bindings[$0.catalogID] ?? $0.catalogID, media: $0.media, name: $0.name) })
            manifestData = try encoder.encode(manifest)
        }
        replacements["manifest.json"] = manifestData
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("\(manifest.packID)-\(manifest.revision)-\(UUID().uuidString).gymrestmedia")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        func header(_ fields: [(UInt32, Int)]) -> Data {
            var result = Data()
            for (value, length) in fields { for shift in 0..<length { result.append(UInt8(truncatingIfNeeded: value >> (shift * 8))) } }
            return result
        }
        var central = Data(); var offset: UInt32 = 0
        do {
            let names = ["manifest.json"] + manifest.files.map(\.path).sorted()
            for path in names {
                guard MediaArchive.validPath(path) else { throw MediaPackFailure.invalid("导出路径不合法。") }
                let data: Data
                if let replacement = replacements[path] { data = replacement }
                else { data = try Data(contentsOf: directory.appendingPathComponent(path)) }
                guard data.count <= 10 * 1024 * 1024 else { throw MediaPackFailure.invalid("导出单资源超过10MiB。") }
                let name = Data(path.utf8)
                let size = UInt32(data.count), crc = crc32(data)
                let local = header([(0x04034b50,4),(20,2),(0x0800,2),(0,2),(0,2),(0,2),(crc,4),(size,4),(size,4),(UInt32(name.count),2),(0,2)])
                try handle.write(contentsOf: local); try handle.write(contentsOf: name); try handle.write(contentsOf: data)
                central.append(header([(0x02014b50,4),(20,2),(20,2),(0x0800,2),(0,2),(0,2),(0,2),(crc,4),(size,4),(size,4),(UInt32(name.count),2),(0,2),(0,2),(0,2),(0,2),(0,4),(offset,4)]))
                central.append(name); offset += UInt32(local.count + name.count + data.count)
                guard Int(offset) <= MediaArchive.maxBytes else { throw MediaPackFailure.invalid("导出超过100MiB。") }
            }
            try handle.write(contentsOf: central)
            try handle.write(contentsOf: header([(0x06054b50,4),(0,2),(0,2),(UInt32(names.count),2),(UInt32(names.count),2),(UInt32(central.count),4),(offset,4),(0,2)]))
            return output
        } catch { try? FileManager.default.removeItem(at: output); throw error }
    }
}
