import Foundation

struct RestTask: Codable, Equatable, Sendable {
    let id: UUID
    let end: Date
    let backend: String
}

enum TimerInspection: Sendable {
    case running(end: Date?)
    case paused(remaining: TimeInterval?)
    case alerting
    case missing
}

@MainActor
protocol TimerService {
    var name: String { get }
    var authorization: String { get async }
    func authorize() async throws
    func start(id: UUID, seconds: Int, context: RestContext?) async throws
    func cancel(id: UUID) async throws
    func inspect(id: UUID) async throws -> TimerInspection
    func status(id: UUID) async throws -> String
}

enum TimerFailure: LocalizedError {
    case denied, invalidDuration
    var errorDescription: String? {
        switch self {
        case .denied: "提醒权限未授权，请在系统设置中检查。"
        case .invalidDuration: "请输入 1 至 86400 之间的整数秒数。"
        }
    }
}

// The technical probe has no training context.
extension TimerService {
    func start(id: UUID, seconds: Int) async throws { try await start(id: id, seconds: seconds, context: nil) }
}
