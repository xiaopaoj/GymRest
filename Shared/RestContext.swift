import Foundation

struct RestContext: Codable, Hashable, Sendable {
    let planName: String
    let exerciseName: String
    let completedSet: Int
    let totalSets: Int
    let nextStep: String
    var kind: String? = nil
}
