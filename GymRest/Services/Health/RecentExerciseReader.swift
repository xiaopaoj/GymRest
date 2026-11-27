import Foundation
#if GYMREST_HEALTHKIT
@preconcurrency import HealthKit
#endif

@MainActor final class RecentExerciseReader {
    #if GYMREST_HEALTHKIT
    private let health = HKHealthStore()
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
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKQuantityType(.appleExerciseTime), predicate: predicate, limit: 500,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { @Sendable _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let result = (samples as? [HKQuantitySample] ?? []).map { sample in
                    ExerciseActivitySample(id: sample.uuid, start: sample.startDate, end: sample.endDate,
                        minutes: sample.quantity.doubleValue(for: .minute()), productType: sample.sourceRevision.productType,
                        userEntered: (sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool) == true)
                }
                continuation.resume(returning: result)
            }
            health.execute(query)
        }
        #else
        throw HealthFailure.buildDisabled
        #endif
    }
}
