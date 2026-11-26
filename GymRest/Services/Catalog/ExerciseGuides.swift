import Foundation

struct ExerciseGuide: Codable, Identifiable, Sendable {
    let catalogID: String
    let name: String
    let family: String
    let setup: String
    let steps: [String]
    let mistakes: [String]
    let notes: [String]
    let references: [String]
    let author: String
    let scope: String
    var id: String { catalogID }
}
struct ExerciseGuides: Codable, Sendable {
    let version: Int
    let items: [ExerciseGuide]
    static func bundled() throws -> Self {
        guard let url = Bundle.main.url(forResource: "ExerciseGuides", withExtension: "json") else { throw CatalogError.invalid }
        let document = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard document.version == 1, Set(document.items.map(\.catalogID)).count == document.items.count,
              document.items.allSatisfy({ $0.steps.count >= 4 && $0.mistakes.count >= 3 && !$0.setup.isEmpty }) else { throw CatalogError.invalid }
        return document
    }
}
