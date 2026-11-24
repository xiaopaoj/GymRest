import Foundation

@MainActor
final class MockTimerService: TimerService {
    let name = "Mock"
    var authorization: String { get async { "mock" } }
    var ids: Set<UUID> = []
    var starts = 0
    func authorize() async throws {}
    func start(id: UUID, seconds: Int) async throws { ids = [id]; starts += 1 }
    func cancel(id: UUID) async throws { ids.remove(id) }
    func status(id: UUID) async throws -> String { ids.contains(id) ? "countdown" : "missing" }
}
