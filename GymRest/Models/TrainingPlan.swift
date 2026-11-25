import Foundation
import SwiftData

struct ExerciseAlternative: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var restSeconds: Int = 90
    var restOverrides: [Int: Int] = [:]
    enum CodingKeys: String, CodingKey { case id, name, restSeconds, restOverrides }
    init(id: UUID = UUID(), name: String, restSeconds: Int = 90, restOverrides: [Int: Int] = [:]) {
        self.id = id; self.name = name; self.restSeconds = restSeconds; self.restOverrides = restOverrides
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        restSeconds = try c.decode(Int.self, forKey: .restSeconds)
        restOverrides = try c.decodeIfPresent([Int: Int].self, forKey: .restOverrides) ?? [:]
    }
    func validate(sets: Int) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 100,
              (1...86400).contains(restSeconds), restOverrides.allSatisfy({ (1...sets).contains($0.key) && (1...86400).contains($0.value) }) else {
            throw TrainingError.invalidExercise
        }
    }
}

struct ExerciseSpec: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var sets: Int = 4
    var restSeconds: Int = 90
    var restAfterLastSet = false
    var restOverrides: [Int: Int] = [:]

    var alternatives: [ExerciseAlternative] = []

    enum CodingKeys: String, CodingKey { case id, name, sets, restSeconds, restAfterLastSet, restOverrides, alternatives }
    init(id: UUID = UUID(), name: String, sets: Int = 4, restSeconds: Int = 90, restAfterLastSet: Bool = false, restOverrides: [Int: Int] = [:], alternatives: [ExerciseAlternative] = []) {
        self.id = id; self.name = name; self.sets = sets; self.restSeconds = restSeconds
        self.restAfterLastSet = restAfterLastSet; self.restOverrides = restOverrides; self.alternatives = alternatives
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        sets = try c.decode(Int.self, forKey: .sets); restSeconds = try c.decode(Int.self, forKey: .restSeconds)
        restAfterLastSet = try c.decode(Bool.self, forKey: .restAfterLastSet)
        restOverrides = try c.decodeIfPresent([Int: Int].self, forKey: .restOverrides) ?? [:]
        alternatives = try c.decodeIfPresent([ExerciseAlternative].self, forKey: .alternatives) ?? []
    }
    func rest(afterSet set: Int) -> Int { restOverrides[set] ?? restSeconds }

    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 100, (1...100).contains(sets), (1...86400).contains(restSeconds),
              restOverrides.allSatisfy({ (1...sets).contains($0.key) && (1...86400).contains($0.value) }) else {
            throw TrainingError.invalidExercise
        }
        guard Set([id] + alternatives.map(\.id)).count == alternatives.count + 1 else { throw TrainingError.invalidExercise }
        for alternative in alternatives { try alternative.validate(sets: sets) }
    }
}

// The ordered Codable value array keeps each exercise's configuration independent.
@Model final class TrainingPlan {
    @Attribute(.unique) var id: UUID
    var name: String
    var position: Int
    var exerciseData: Data
    init(name: String, position: Int, exercises: [ExerciseSpec] = []) throws {
        id = UUID(); self.name = name; self.position = position
        exerciseData = try JSONEncoder().encode(exercises)
    }
    func exercises() throws -> [ExerciseSpec] { try JSONDecoder().decode([ExerciseSpec].self, from: exerciseData) }
    func setExercises(_ values: [ExerciseSpec]) throws {
        for value in values { try value.validate() }
        exerciseData = try JSONEncoder().encode(values)
    }
}

@Model final class LibraryPreferences {
    @Attribute(.unique) var key: String
    var defaultSets: Int
    var defaultRest: Int
    var notificationFallback: Bool
    var keepScreenOn: Bool
    init() {
        key = "preferences"; defaultSets = 4; defaultRest = 90
        notificationFallback = false; keepScreenOn = false
    }
}

@Model final class ActiveTraining {
    @Attribute(.unique) var key: String
    var payload: Data
    init(payload: Data) { key = "active"; self.payload = payload }
}

enum TrainingError: LocalizedError {
    case invalidExercise, emptyPlan, activeSession, missingReminder, invalidSession
    var errorDescription: String? {
        switch self {
        case .invalidSession: "保存的训练状态不完整。请保留数据并反馈，避免覆盖训练进度。"
        case .invalidExercise: "动作名称不能为空或超过100字，组数须为1–100，休息须为1–86400秒，按组覆盖须对应有效组号。"
        case .emptyPlan: "请先向计划中添加训练动作。"
        case .activeSession: "请先继续或结束当前训练。"
        case .missingReminder: "系统中没有当前休息提醒。请重新开始休息，或跳过休息继续训练。"
        }
    }
}
