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
    private(set) var busy = false
    private(set) var samples: [ExerciseActivitySample] = []
    private(set) var checkedAt: Date?
    private(set) var issue: String?

    init(defaults: UserDefaults = .standard, authorize: @escaping @MainActor () async throws -> Void,
         fetch: @escaping @MainActor (Date) async throws -> [ExerciseActivitySample]) {
        self.defaults = defaults; self.authorize = authorize; self.fetch = fetch
        authorizationRequested = defaults.bool(forKey: Self.authorizationKey)
    }
    func requestAccess() async {
        guard !busy else { return }; busy = true
        do {
            try await authorize()
            // HealthKit does not reveal read denial. This flag records only that
            // the request returned, never that read access was granted.
            authorizationRequested = true; defaults.set(true, forKey: Self.authorizationKey)
            issue = nil
        } catch { samples = []; issue = error.localizedDescription; busy = false; return }
        busy = false
        if authorizationRequested { await refresh() }
    }
    func refresh(at now: Date = Date()) async {
        guard authorizationRequested, !busy else { return }; busy = true
        defer { busy = false }
        do {
            let values = try await fetch(now)
            guard !Task.isCancelled else { return }
            samples = values; checkedAt = now; issue = nil
        } catch {
            guard !Task.isCancelled else { return }
            samples = []; checkedAt = now; issue = error.localizedDescription
        }
    }
    func evidence(at now: Date) -> ExerciseActivityEvidence {
        ExerciseActivityEvidence.analyze(samples, at: now)
    }
}
