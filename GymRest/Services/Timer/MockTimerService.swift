import Foundation

@MainActor
final class MockTimerService: TimerService {
    let name = "Mock"
    var authorization: String { get async { "mock" } }
    var ids: Set<UUID> = []
    var starts = 0
    var lastContext: RestContext?
    var failStart = false
    var failCancel = false
    var inspection: TimerInspection?
    func inspect(id: UUID) async throws -> TimerInspection { inspection ?? (ids.contains(id) ? .running(end: nil) : .missing) }
    func authorize() async throws {}
    func start(id: UUID, seconds: Int, context: RestContext?) async throws { if failStart { throw TimerFailure.denied }; ids = [id]; starts += 1; lastContext = context }
    func cancel(id: UUID) async throws { if failCancel { throw TimerFailure.denied }; ids.remove(id) }
    func status(id: UUID) async throws -> String { ids.contains(id) ? "countdown" : "missing" }
}
