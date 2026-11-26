import XCTest
@testable import GymRest

@MainActor final class MediaPackTests: XCTestCase {
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func pack(revision: Int = 1, title: String = "测试包", id: String = "test.media", status: String = "approved") throws -> PreparedMediaPack {
        let directory = try temporary()
        let original = try XCTUnwrap(TestMediaResources.assetURL("wg-plank-1.png"))
        let png = try Data(contentsOf: original)
        let files: [String: Data] = ["frames/test.png": png, "credits/LICENSE.txt": Data("CC BY-SA 4.0 · Test".utf8), "credits/Sources.json": Data("{}".utf8)]
        for (name, data) in files {
            let url = directory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        let media = CatalogMedia(status: status, reviewNote: "静态示意", allowsPlayback: false, lightBackground: false,
            frameAssets: status == "approved" ? ["test.png"] : [], animationAsset: nil, equipmentAsset: nil,
            author: "Test", licenseURL: "https://creativecommons.org/licenses/by-sa/4.0/", sourceURL: "https://example.com/source")
        let manifest = MediaPackManifest(format: "GymRestMedia", schemaVersion: 1, packID: id, revision: revision, minimumAppBuild: 8,
            title: title, files: files.sorted { $0.key < $1.key }.map { .init(path: $0.key, bytes: $0.value.count, sha256: MediaArchive.hash($0.value)) },
            artwork: [.init(catalogID: "guide-plank", media: media)])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: directory.appendingPathComponent("manifest.json"))
        return PreparedMediaPack(directory: directory, manifest: manifest, manifestHash: MediaArchive.hash(data), bytes: files.values.reduce(0) { $0 + $1.count })
    }
    func testStoredZipExportImportRoundTripAndHashValidation() throws {
        let original = try pack(), url = try MediaPackExporter.export(directory: original.directory)
        defer { try? FileManager.default.removeItem(at: url) }
        let parsed = try MediaArchive.prepare(Data(contentsOf: url), build: 8, destination: temporary().appendingPathComponent("parsed"))
        XCTAssertEqual(parsed.manifestHash, original.manifestHash)
        XCTAssertEqual(parsed.manifest.artwork[0].media.frameAssets, ["test.png"])
        XCTAssertEqual(MediaPackExporter.crc32(Data("123456789".utf8)), 0xcbf43926)
    }
    func testCorruptArchiveAndUnsupportedBuildAreRejected() throws {
        let original = try pack(), url = try MediaPackExporter.export(directory: original.directory)
        defer { try? FileManager.default.removeItem(at: url) }
        var data = try Data(contentsOf: url)
        XCTAssertThrowsError(try MediaArchive.prepare(data, build: 7))
        data[0] = 0
        XCTAssertThrowsError(try MediaArchive.prepare(data, build: 8))
        XCTAssertThrowsError(try MediaArchive.prepare(Data(), build: 8))
        for path in ["../image.png", "/tmp/image.png", "a//b", "a/./b", "a\\b", "a/../b", "C:asset"] { XCTAssertFalse(MediaArchive.validPath(path)) }
    }
    func testPayloadTamperCannotCreateInstalledDirectory() throws {
        let original = try pack(), url = try MediaPackExporter.export(directory: original.directory)
        defer { try? FileManager.default.removeItem(at: url) }
        var data = try Data(contentsOf: url)
        let marker = try XCTUnwrap(data.range(of: Data("CC BY-SA 4.0 · Test".utf8)))
        data[marker.lowerBound] ^= 1
        let destination = try temporary().appendingPathComponent("invalid")
        XCTAssertThrowsError(try MediaArchive.prepare(data, build: 8, destination: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }
    func testInstallReopenRollbackAndSameVersionConflict() throws {
        let root = try temporary(), store = MediaStore(root: root)
        try store.install(pack())
        try store.install(pack()) // Exact same revision/content is idempotent.
        XCTAssertEqual(store.selections.count, 1)
        XCTAssertThrowsError(try store.install(pack(title: "同版本不同内容")))
        try store.install(pack(revision: 2))
        XCTAssertEqual(store.selections[0].previous, 1)
        let restored = MediaStore(root: root)
        XCTAssertNil(restored.issue); XCTAssertEqual(restored.selections[0].revision, 2)
        try restored.rollback("test.media")
        XCTAssertEqual(restored.selections[0].revision, 1)
        XCTAssertThrowsError(try restored.install(pack(revision: 0)))
    }
    func testPartialPackOverrideAndWithheldMappingCannotFallBack() throws {
        let store = MediaStore(root: try temporary()), catalog = try ExerciseCatalog.bundled()
        try store.install(pack(id: MediaStore.officialID))
        let plank = try XCTUnwrap(catalog.item("guide-plank"))
        XCTAssertEqual(store.selection(for: plank).frames.count, 1)
        try store.install(pack(id: "user.override", status: "pending"))
        XCTAssertTrue(store.selection(for: plank).frames.isEmpty)
        XCTAssertFalse(store.selection(for: plank).media.approved)
        try store.setEnabled("user.override", enabled: false)
        XCTAssertEqual(store.selection(for: plank).frames.count, 1)
        try store.remove("user.override")
        XCTAssertEqual(store.selections.count, 1)
    }
    func testCorruptIndexIsNotSilentlyReplaced() throws {
        let root = try temporary()
        try Data("invalid".utf8).write(to: root.appendingPathComponent("index.json"))
        let store = MediaStore(root: root)
        XCTAssertNotNil(store.issue)
        XCTAssertThrowsError(try store.install(pack()))
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("index.json"), encoding: .utf8), "invalid")
    }
    func testOfficialRuntimePackContainsOnlyReviewedDisplayFrames() throws {
        let url = try XCTUnwrap(TestMediaResources.officialPack)
        let prepared = try MediaArchive.prepare(Data(contentsOf: url), build: 8, destination: temporary().appendingPathComponent("official"))
        XCTAssertEqual(prepared.manifest.packID, MediaStore.officialID)
        XCTAssertEqual(prepared.manifest.artwork.count, 306)
        XCTAssertEqual(prepared.manifest.files.filter { $0.path.hasPrefix("frames/") }.count, 775)
        let close = try XCTUnwrap(prepared.manifest.artwork.first { $0.catalogID == "guide-close-grip-bench-press" })
        XCTAssertEqual(close.media.frameAssets, ["wg-close-grip-bench-press-1.png", "wg-close-grip-bench-press-3.png"])
    }
    func testNameOnlyMappingAndExportedLocalBindingRemainPortable() throws {
        let original = try pack()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: original.directory.appendingPathComponent("manifest.json"))) as? [String: Any])
        var entries = try XCTUnwrap(object["artwork"] as? [[String: Any]])
        entries[0]["catalogID"] = nil; entries[0]["name"] = "平板支撑"; object["artwork"] = entries
        let decoded = try JSONDecoder().decode(MediaPackManifest.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(decoded.artwork[0].catalogID.hasPrefix("name:"))
        let url = try MediaPackExporter.export(directory: original.directory, bindings: ["guide-plank": "guide-side-plank"])
        defer { try? FileManager.default.removeItem(at: url) }
        let parsed = try MediaArchive.prepare(Data(contentsOf: url), build: 8, destination: temporary().appendingPathComponent("exported"))
        XCTAssertTrue(parsed.manifest.packID.hasPrefix("user.mapped-"))
        XCTAssertEqual(parsed.manifest.artwork[0].catalogID, "guide-side-plank")
        XCTAssertNotEqual(parsed.manifestHash, original.manifestHash)
    }
    func testEncryptedCompressedAndSymlinkEntriesAreRejected() throws {
        let original = try pack(), url = try MediaPackExporter.export(directory: original.directory)
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = try Data(contentsOf: url)
        let central = try XCTUnwrap(bytes.range(of: Data([0x50, 0x4b, 0x01, 0x02]), options: .backwards)).lowerBound
        var compressed = bytes; compressed[central + 10] = 8
        XCTAssertThrowsError(try MediaArchive.prepare(compressed, build: 8))
        var encrypted = bytes; encrypted[central + 8] = 1
        XCTAssertThrowsError(try MediaArchive.prepare(encrypted, build: 8))
        var link = bytes; link[central + 40] = 0xff; link[central + 41] = 0xa1
        XCTAssertThrowsError(try MediaArchive.prepare(link, build: 8))
        var path = bytes; path[30] = 46; path[31] = 46; path[32] = 47
        XCTAssertThrowsError(try MediaArchive.prepare(path, build: 8))
    }

}
