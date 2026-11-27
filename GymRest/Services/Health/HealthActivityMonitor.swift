import Foundation
import Observation

@MainActor @Observable final class HealthActivityMonitor {
    static let shared: HealthActivityMonitor = {
        let reader = RecentExerciseReader()
        return HealthActivityMonitor(authorize: { try await reader.authorize() }, fetch: { try await reader.samples(at: $0) })
    }()
    private static let authorizationKey = "healthActivityAuthorizationRequested"
    private let defaults: UserDefaults
    private let authorize: @MainActor () async throws -> Void
    private let fetch: @MainActor (Date) async throws -> [ExerciseActivitySample]
    private(set) var authorizationRequested: Bool
    enum Phase: Equatable { case idle, authorizing, reading, finished, failed }
    private(set) var phase: Phase = .idle
    private(set) var resultCount = 0
    private let authorizationTimeout: Duration
    private let queryTimeout: Duration
    private(set) var busy = false
    private(set) var samples: [ExerciseActivitySample] = []
    private(set) var checkedAt: Date?
    private(set) var issue: String?

    init(defaults: UserDefaults = .standard, authorize: @escaping @MainActor () async throws -> Void,
         fetch: @escaping @MainActor (Date) async throws -> [ExerciseActivitySample],
         authorizationTimeout: Duration = .seconds(90), queryTimeout: Duration = .seconds(20)) {
        self.defaults = defaults; self.authorize = authorize; self.fetch = fetch
        self.authorizationTimeout = authorizationTimeout; self.queryTimeout = queryTimeout
        authorizationRequested = defaults.bool(forKey: Self.authorizationKey)
    }
    func requestAccess() async {
        guard !busy else { return }; busy = true; phase = .authorizing; issue = nil
        do {
            try await HealthOperationDeadline.run(timeout: authorizationTimeout, operation: authorize)
            // HealthKit does not reveal read denial. This flag records only that
            // the request returned, never that read access was granted.
            authorizationRequested = true; defaults.set(true, forKey: Self.authorizationKey)
            issue = nil
        } catch { samples = []; phase = .failed; issue = error.localizedDescription; busy = false; return }
        busy = false
        if authorizationRequested { await refresh() }
    }
    func refresh(at now: Date = Date()) async {
        guard authorizationRequested, !busy else { return }; busy = true; phase = .reading
        defer { busy = false }
        do {
            let fetch = self.fetch
            let values = try await HealthOperationDeadline.run(timeout: queryTimeout) { try await fetch(now) }
            guard !Task.isCancelled else { phase = .idle; return }
            samples = values; resultCount = values.count; checkedAt = now; phase = .finished; issue = nil
        } catch {
            guard !Task.isCancelled else { phase = .idle; return }
            samples = []; resultCount = 0; checkedAt = now; phase = .failed; issue = error.localizedDescription
        }
    }
    var feedback: String {
        switch phase {
        case .idle: "尚未查询近期锻炼数据"
        case .authorizing: "正在向系统请求健康读取；若权限已设置，系统可能不再弹窗"
        case .reading: "正在查询近期锻炼数据…"
        case .finished: resultCount == 0 ? "查询已完成，未返回近期锻炼样本；可能未授权或尚未同步" : "查询已完成，返回 \(resultCount) 条近期锻炼样本"
        case .failed: "健康读取未完成，请查看下方原因并重试"
        }
    }
    func evidence(at now: Date) -> ExerciseActivityEvidence {
        ExerciseActivityEvidence.analyze(samples, at: now)
    }
}
