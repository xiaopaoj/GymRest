import Foundation
import SwiftData

struct ExerciseAlternative: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var restSeconds: Int = 90
    var restOverrides: [Int: Int] = [:]
    var catalogID: String?
    var prescription: SetValues?
    enum CodingKeys: String, CodingKey { case id, name, restSeconds, restOverrides, catalogID, prescription }
    init(id: UUID = UUID(), name: String, restSeconds: Int = 90, restOverrides: [Int: Int] = [:], catalogID: String? = nil, prescription: SetValues? = nil) {
        self.id = id; self.name = name; self.restSeconds = restSeconds; self.restOverrides = restOverrides
        self.catalogID = catalogID; self.prescription = prescription
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        restSeconds = try c.decode(Int.self, forKey: .restSeconds)
        restOverrides = try c.decodeIfPresent([Int: Int].self, forKey: .restOverrides) ?? [:]
        catalogID = try c.decodeIfPresent(String.self, forKey: .catalogID)
        prescription = try c.decodeIfPresent(SetValues.self, forKey: .prescription)
    }
    func validate(sets: Int) throws {
        try prescription?.validate()
        guard catalogID.map({ !$0.isEmpty && $0.count <= 100 }) ?? true else { throw TrainingError.invalidExercise }
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
    // nil preserves legacy final-set behavior. Zero explicitly skips the transition.
    var transitionRestSeconds: Int?
    var restOverrides: [Int: Int] = [:]

    var catalogID: String?
    var prescription: SetValues?
    var alternatives: [ExerciseAlternative] = []

    enum CodingKeys: String, CodingKey { case id, name, sets, restSeconds, restAfterLastSet, transitionRestSeconds, restOverrides, alternatives, catalogID, prescription }
    init(id: UUID = UUID(), name: String, sets: Int = 4, restSeconds: Int = 90, restAfterLastSet: Bool = false, restOverrides: [Int: Int] = [:], alternatives: [ExerciseAlternative] = [], transitionRestSeconds: Int? = nil, catalogID: String? = nil, prescription: SetValues? = nil) {
        self.id = id; self.name = name; self.sets = sets; self.restSeconds = restSeconds
        self.restAfterLastSet = restAfterLastSet; self.restOverrides = restOverrides; self.alternatives = alternatives
        self.transitionRestSeconds = transitionRestSeconds
        self.catalogID = catalogID; self.prescription = prescription
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        sets = try c.decode(Int.self, forKey: .sets); restSeconds = try c.decode(Int.self, forKey: .restSeconds)
        restAfterLastSet = try c.decode(Bool.self, forKey: .restAfterLastSet)
        transitionRestSeconds = try c.decodeIfPresent(Int.self, forKey: .transitionRestSeconds)
        restOverrides = try c.decodeIfPresent([Int: Int].self, forKey: .restOverrides) ?? [:]
        alternatives = try c.decodeIfPresent([ExerciseAlternative].self, forKey: .alternatives) ?? []
        catalogID = try c.decodeIfPresent(String.self, forKey: .catalogID)
        prescription = try c.decodeIfPresent(SetValues.self, forKey: .prescription)
    }
    func rest(afterSet set: Int) -> Int { restOverrides[set] ?? restSeconds }
    func profileKey(for values: SetValues) -> String {
        // Encoding an array avoids delimiter collisions in user-entered equipment names.
        let parts = [catalogID ?? ("custom:" + ExerciseNames.canonical(name, catalogID: nil)), values.kind.rawValue, values.unit.rawValue, values.equipmentNote]
        return (try? JSONEncoder().encode(parts).base64EncodedString()) ?? ""
    }

    func validate() throws {
        try prescription?.validate()
        guard catalogID.map({ !$0.isEmpty && $0.count <= 100 }) ?? true else { throw TrainingError.invalidExercise }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 100, (1...100).contains(sets), (1...86400).contains(restSeconds),
              restOverrides.allSatisfy({ (1...sets).contains($0.key) && (1...86400).contains($0.value) }) else {
            throw TrainingError.invalidExercise
        }
        if let transitionRestSeconds, !(0...86400).contains(transitionRestSeconds) { throw TrainingError.invalidExercise }
        guard Set([id] + alternatives.map(\.id)).count == alternatives.count + 1 else { throw TrainingError.invalidExercise }
        for alternative in alternatives { try alternative.validate(sets: sets) }
    }
}

// The ordered Codable value array keeps each exercise's configuration independent.
@Model final class TrainingPlan {
    var programID: UUID?
    @Attribute(.unique) var id: UUID
    var name: String
    var position: Int
    var exerciseData: Data
    init(name: String, position: Int, exercises: [ExerciseSpec] = []) throws {
        id = UUID(); self.name = name; self.position = position
        exerciseData = try JSONEncoder().encode(ExerciseNames.standardize(exercises))
    }
    func exercises() throws -> [ExerciseSpec] { try JSONDecoder().decode([ExerciseSpec].self, from: exerciseData) }
    func setExercises(_ values: [ExerciseSpec]) throws {
        for value in values { try value.validate() }
        exerciseData = try JSONEncoder().encode(ExerciseNames.standardize(values))
    }
}

@Model final class LibraryPreferences {
    @Attribute(.unique) var key: String
    var defaultSets: Int
    var defaultRest: Int
    var notificationFallback: Bool
    var keepScreenOn: Bool
    // nil on pre-cleanup stores; new libraries never seed empty placeholders.
    var legacyPlaceholdersRemoved: Bool?
    init() {
        key = "preferences"; defaultSets = 4; defaultRest = 90
        notificationFallback = false; keepScreenOn = false
        legacyPlaceholdersRemoved = true
    }
}

@Model final class ActiveTraining {
    @Attribute(.unique) var key: String
    var payload: Data
    init(payload: Data) { key = "active"; self.payload = payload }
}

enum TrainingError: LocalizedError {
    case invalidExercise, emptyPlan, activeSession, missingReminder, invalidSession, uncalibratedTimer
    var errorDescription: String? {
        switch self {
        case .uncalibratedTimer: "系统计时已恢复，暂时无法读取截止时间。请稍后刷新，或重新开始当前休息。"
        case .invalidSession: "保存的训练状态不完整。请保留数据并反馈，避免覆盖训练进度。"
        case .invalidExercise: "动作名称须为1–100字，组数须为1–100，组间休息须为1–86400秒，动作间休息须为0–86400秒，按组覆盖须对应有效组号。"
        case .emptyPlan: "请先向计划中添加训练动作。"
        case .activeSession: "请先继续或结束当前训练。"
        case .missingReminder: "系统中没有当前休息提醒。请重新开始休息，或跳过休息继续训练。"
        }
    }
}
