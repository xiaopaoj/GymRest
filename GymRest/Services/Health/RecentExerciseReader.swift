import Foundation
#if GYMREST_HEALTHKIT
@preconcurrency import HealthKit
#endif

@MainActor final class RecentExerciseReader {
    #if GYMREST_HEALTHKIT
    private let health = HKHealthStore()
    private var activeSampleRequest: SampleRequest?
    #endif
    func authorize() async throws {
        #if GYMREST_HEALTHKIT
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthFailure.unavailable }
        try await health.requestAuthorization(toShare: [], read: [HKQuantityType(.appleExerciseTime)])
        #else
        throw HealthFailure.buildDisabled
        #endif
    }
    func samples(at now: Date) async throws -> [ExerciseActivitySample] {
        #if GYMREST_HEALTHKIT
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthFailure.unavailable }
        let predicate = HKQuery.predicateForSamples(withStart: now.addingTimeInterval(-ExerciseActivityEvidence.lookback), end: now, options: [.strictStartDate, .strictEndDate])
        try Task.checkCancellation()
        // Stop a timed-out request before starting a retry even if its
        // cancellation handler has not reached the main actor yet.
        activeSampleRequest?.cancel()
        let request = SampleRequest(health: health)
        activeSampleRequest = request
        defer {
            if activeSampleRequest === request { activeSampleRequest = nil }
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                request.start(predicate: predicate, continuation: continuation)
            }
        } onCancel: {
            Task { @MainActor in request.cancel() }
        }
        #else
        throw HealthFailure.buildDisabled
        #endif
    }
    #if GYMREST_HEALTHKIT
    @MainActor private final class SampleRequest {
        private let health: HKHealthStore
        private var query: HKSampleQuery?
        private var continuation: CheckedContinuation<[ExerciseActivitySample], any Error>?

        init(health: HKHealthStore) {
            self.health = health
        }

        func start(predicate: NSPredicate, continuation: CheckedContinuation<[ExerciseActivitySample], any Error>) {
            self.continuation = continuation
            let query = HKSampleQuery(sampleType: HKQuantityType(.appleExerciseTime), predicate: predicate, limit: 500,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { @Sendable [weak self] _, samples, error in
                if let error {
                    Task { @MainActor in self?.finish(.failure(error)) }
                    return
                }
                let result = (samples as? [HKQuantitySample] ?? []).map { sample in
                    ExerciseActivitySample(id: sample.uuid, start: sample.startDate, end: sample.endDate,
                        minutes: sample.quantity.doubleValue(for: .minute()), productType: sample.sourceRevision.productType,
                        userEntered: (sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool) == true)
                }
                Task { @MainActor in self?.finish(.success(result)) }
            }
            self.query = query
            health.execute(query)
        }

        func cancel() {
            if let query { health.stop(query) }
            finish(.failure(CancellationError()))
        }

        private func finish(_ result: Result<[ExerciseActivitySample], any Error>) {
            guard let continuation else { return }
            self.continuation = nil
            query = nil
            continuation.resume(with: result)
        }
    }
    #endif
}
