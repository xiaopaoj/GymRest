import Foundation

/// Unlike a task group, this boundary can return on timeout even if an Apple
/// authorization/query operation does not cooperate with task cancellation.
@MainActor enum HealthOperationDeadline {
    static func run<Value: Sendable>(timeout: Duration, operation: @escaping @MainActor () async throws -> Value) async throws -> Value {
        let pending = Pending<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending.start(continuation, timeout: timeout, operation: operation)
            }
        } onCancel: {
            Task { @MainActor in pending.finish(.failure(CancellationError())) }
        }
    }
    @MainActor private final class Pending<Value: Sendable> {
        private var continuation: CheckedContinuation<Value, any Error>?
        private var work: Task<Void, Never>?
        private var deadline: Task<Void, Never>?
        private var finished = false
        func start(_ continuation: CheckedContinuation<Value, any Error>, timeout: Duration,
                   operation: @escaping @MainActor () async throws -> Value) {
            guard !finished else { continuation.resume(throwing: CancellationError()); return }
            self.continuation = continuation
            work = Task { @MainActor in
                do { let value = try await operation(); finish(.success(value)) }
                catch { finish(.failure(error)) }
            }
            deadline = Task { @MainActor in
                do { try await Task.sleep(for: timeout) } catch { return }
                finish(.failure(HealthOperationTimeout()))
            }
        }
        func finish(_ result: Result<Value, any Error>) {
            guard !finished else { return }; finished = true
            let saved = continuation; continuation = nil
            work?.cancel(); deadline?.cancel(); work = nil; deadline = nil
            saved?.resume(with: result)
        }
    }
}
struct HealthOperationTimeout: LocalizedError {
    var errorDescription: String? { "健康读取暂未返回结果，请检查健康权限后重试；系统授权页若仍打开，请先完成选择。" }
}
