import Foundation

enum WorkoutMatching {
    static func window(start: Date, end: Date) throws -> DateInterval {
        guard start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite, end >= start else { throw HealthFailure.invalidInterval }
        return DateInterval(start: start.addingTimeInterval(-900), end: end.addingTimeInterval(900))
    }
    static func ranked(_ values: [WorkoutCandidate], start: Date, end: Date) throws -> [WorkoutCandidate] {
        let window = try window(start: start, end: end)
        var seen: Set<UUID> = []
        return values.filter {
            $0.start.timeIntervalSince1970.isFinite && $0.end.timeIntervalSince1970.isFinite && $0.end > $0.start &&
            $0.end >= window.start && $0.start <= window.end && seen.insert($0.id).inserted
        }.sorted { a, b in
            let x = a.overlapScore(start: start, end: end), y = b.overlapScore(start: start, end: end)
            if x != y { return x > y }
            let ax = abs(a.start.timeIntervalSince(start)), bx = abs(b.start.timeIntervalSince(start))
            return ax == bx ? a.id.uuidString < b.id.uuidString : ax < bx
        }
    }
}

/// Authorization and fetching are injectable for tests. No query or write occurs
/// until the explicit user action calls candidates; absence of data is not a denial verdict.
@MainActor struct WorkoutQueryRunner {
    let authorize: @MainActor () async throws -> Void
    let fetch: @MainActor (DateInterval) async throws -> [WorkoutCandidate]
    func candidates(start: Date, end: Date) async throws -> [WorkoutCandidate] {
        let interval = try WorkoutMatching.window(start: start, end: end)
        try Task.checkCancellation()
        try await authorize()
        try Task.checkCancellation()
        let values = try await fetch(interval)
        try Task.checkCancellation()
        return try WorkoutMatching.ranked(values, start: start, end: end)
    }
}
