import Foundation

final class TestMediaResources {
    static func assetURL(_ filename: String) -> URL? {
        guard filename == (filename as NSString).lastPathComponent, !filename.contains("..") else { return nil }
        return Bundle(for: TestMediaResources.self).url(forResource: (filename as NSString).deletingPathExtension,
            withExtension: (filename as NSString).pathExtension, subdirectory: "TestMediaFrames")
    }
    static var officialPack: URL? { Bundle(for: TestMediaResources.self).url(forResource: "GymRest-Official", withExtension: "gymrestmedia") }
}
