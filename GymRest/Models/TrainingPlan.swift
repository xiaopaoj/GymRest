import Foundation
import SwiftData

struct ExerciseSpec: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var sets: Int = 4
    var restSeconds: Int = 90
    var restAfterLastSet = false

    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 100, (1...100).contains(sets), (1...86400).contains(restSeconds) else {
            throw TrainingError.invalidExercise
        }
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
        case .invalidExercise: "动作名称不能为空或超过100字，组数须为1–100，休息须为1–86400秒。"
        case .emptyPlan: "请先向计划中添加训练动作。"
        case .activeSession: "请先继续或结束当前训练。"
        case .missingReminder: "系统中没有当前休息提醒。请重新开始休息，或跳过休息继续训练。"
        }
    }
}
