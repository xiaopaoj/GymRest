import Foundation

enum CompanionFailure: LocalizedError {
    case invalid, unavailable, expired, busy, wrongSession
    case invalidMessage(String)
    var errorDescription: String? {
        switch self {
        case .invalidMessage(let message): message
        case .invalid: "配对消息不完整或版本不兼容，请更新两端App。"
        case .unavailable: "暂时无法连接另一台设备，请确认两端GymRest已安装并打开。"
        case .expired: "请求已过期，请从手机重新发起。"
        case .busy: "已有GymRest手表记录，请先处理当前记录。"
        case .wrongSession: "训练已变化，旧操作未执行，请刷新进度。"
        }
    }
}
struct PhoneTrainingSnapshot: Codable, Equatable, Sendable {
    let trainingID: UUID
    let interactionID: UUID
    let sequence: Int
    let sentAt: Date
    let plan: String
    let exercise: String
    let currentSet: Int
    let sets: Int
    let completedSets: Int
    let totalSets: Int
    let phase: String
    let part: String
    let completionTitle: String
    let values: String
    let durationSeconds: Int?
    let effortStatus: String?
    let effortRegistered: Bool
    let effortEnd: Date?
    let restEnd: Date?
    let remaining: Int
    let reminderRegistered: Bool
    func validate() throws {
        guard (1...100).contains(plan.count), (1...100).contains(exercise.count), part.count <= 100, completionTitle.count <= 100, values.count <= 300,
              (1...100).contains(sets), (0...sets).contains(currentSet), (0...1_000_000_000).contains(completedSets),
              (1...1_000_000_000).contains(totalSets), completedSets <= totalSets, (0...86400).contains(remaining), sequence >= 0,
              ["training", "resting", "paused", "completed"].contains(phase),
              durationSeconds.map({ (1...86400).contains($0) }) ?? true,
              effortStatus.map({ ["running", "paused", "ready"].contains($0) }) ?? true,
              [sentAt, effortEnd, restEnd].compactMap({ $0 }).allSatisfy({ $0.timeIntervalSince1970.isFinite }) else { throw CompanionFailure.invalid }
    }
    func isFresh(at now: Date) -> Bool { (-5...45).contains(now.timeIntervalSince(sentAt)) }
}
struct WatchStartRequest: Codable, Equatable, Sendable {
    let id: UUID
    let trainingID: UUID
    let createdAt: Date
    let expiresAt: Date
    let title: String
    func validate() throws {
        guard (1...100).contains(title.count), createdAt.timeIntervalSince1970.isFinite, expiresAt.timeIntervalSince1970.isFinite,
              (1...120).contains(expiresAt.timeIntervalSince(createdAt)) else { throw CompanionFailure.invalid }
    }
    func isFresh(at now: Date) -> Bool { now >= createdAt.addingTimeInterval(-5) && now <= expiresAt }
}
struct WatchWorkoutStatus: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable {
        case starting, running, paused, ending, saved, discarded, failed
        var terminal: Bool { self == .saved || self == .discarded || self == .failed }
        var title: String {
            switch self {
            case .starting: "手表准备中"
            case .running: "手表正在记录"
            case .paused: "手表记录暂停"
            case .ending: "手表正在保存"
            case .saved: "手表记录已保存"
            case .discarded: "手表记录已丢弃"
            case .failed: "手表记录遇到问题"
            }
        }
    }
    let trainingID: UUID
    let runID: UUID
    let sequence: Int
    let phase: Phase
    let sentAt: Date
    let start: Date?
    let end: Date?
    let workoutID: UUID?
    let heartRate: Double?
    let activeEnergy: Double?
    let issue: String?
    var controlToken: UUID? = nil
    var startRequestID: UUID? = nil
    func validate() throws {
        guard sequence > 0, issue.map({ $0.count <= 300 }) ?? true,
              [sentAt, start, end].compactMap({ $0 }).allSatisfy({ $0.timeIntervalSince1970.isFinite }),
              heartRate.map({ $0.isFinite && (0...400).contains($0) }) ?? true,
              activeEnergy.map({ $0.isFinite && (0...100000).contains($0) }) ?? true else { throw CompanionFailure.invalid }
        if let start, let end, end < start { throw CompanionFailure.invalid }
        if phase == .saved { guard workoutID != nil, start != nil, end != nil else { throw CompanionFailure.invalid } }
    }
    func isFresh(at now: Date) -> Bool { (-5...45).contains(now.timeIntervalSince(sentAt)) }
    func supersedes(_ old: Self?) -> Bool {
        guard let old else { return true }
        if old.runID == runID { return sequence > old.sequence && (!old.phase.terminal || phase == old.phase) }
        // A delayed receipt may still be stored separately, but must not replace a new live run.
        return old.phase.terminal && sentAt > old.sentAt
    }
}
struct WatchCommand: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case hello, requestRecording, trainingAction, pauseRecording, resumeRecording, saveRecording, discardRecording }
    let id: UUID
    let kind: Kind
    let trainingID: UUID?
    let runID: UUID?
    let interactionID: UUID?
    let action: String?
    let sentAt: Date
    let requestedEnd: Date?
    var controlToken: UUID? = nil
    init(kind: Kind, trainingID: UUID? = nil, runID: UUID? = nil, interactionID: UUID? = nil, action: String? = nil, sentAt: Date = Date(), requestedEnd: Date? = nil, controlToken: UUID? = nil) {
        id = UUID(); self.kind = kind; self.trainingID = trainingID; self.runID = runID; self.interactionID = interactionID
        self.action = action; self.sentAt = sentAt; self.requestedEnd = requestedEnd; self.controlToken = controlToken
    }
    func validate() throws {
        guard sentAt.timeIntervalSince1970.isFinite, requestedEnd.map({ $0.timeIntervalSince1970.isFinite }) ?? true else { throw CompanionFailure.invalid }
        if kind != .hello { guard trainingID != nil else { throw CompanionFailure.invalid } }
        if [.pauseRecording, .resumeRecording, .saveRecording, .discardRecording].contains(kind) { guard runID != nil else { throw CompanionFailure.invalid } }
        if kind == .trainingAction {
            guard interactionID != nil, let action, ["completeSet", "pauseRest", "resumeRest", "retryRest", "addRest", "finishRest", "startEffort", "pauseEffort", "resumeEffort"].contains(action) else { throw CompanionFailure.invalid }
        }
    }
    func isFresh(at now: Date) -> Bool {
        // Only a save for one exact run may be queued while disconnected.
        kind == .saveRecording || (-5...30).contains(now.timeIntervalSince(sentAt))
    }
    func targets(_ status: WatchWorkoutStatus, at now: Date) -> Bool {
        trainingID == status.trainingID && runID == status.runID && isFresh(at: now) &&
            (kind == .saveRecording || (controlToken != nil && controlToken == status.controlToken))
    }
}
struct CompanionPacket: Codable, Sendable {
    var version = 1
    var command: WatchCommand?
    var training: PhoneTrainingSnapshot?
    var startRequest: WatchStartRequest?
    var workout: WatchWorkoutStatus?
    var issue: String?
    func encoded() throws -> Data {
        try validate()
        let data = try JSONEncoder().encode(self)
        guard data.count <= 48 * 1024 else { throw CompanionFailure.invalid }
        return data
    }
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 48 * 1024 else { throw CompanionFailure.invalid }
        let packet = try JSONDecoder().decode(Self.self, from: data); try packet.validate(); return packet
    }
    func validate() throws {
        guard version == 1, issue.map({ $0.count <= 300 }) ?? true else { throw CompanionFailure.invalid }
        try command?.validate(); try training?.validate(); try startRequest?.validate(); try workout?.validate()
    }
}
// Apple delegate callbacks may arrive on arbitrary queues. Retain only their reply
// closure in this explicit bridge; invoke it once after main-actor processing.
struct CompanionReply: @unchecked Sendable {
    let send: (Data) -> Void
}
