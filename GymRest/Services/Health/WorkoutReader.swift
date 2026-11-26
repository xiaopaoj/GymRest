import Foundation
#if GYMREST_HEALTHKIT
import HealthKit
#endif

struct WorkoutCandidate: Identifiable, Sendable {
    let id: UUID
    let start: Date
    let end: Date
    let title: String
    let source: String
    let device: String?
    func overlapScore(start localStart: Date, end localEnd: Date) -> Double {
        guard end > start, localEnd >= localStart, start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite, localStart.timeIntervalSince1970.isFinite, localEnd.timeIntervalSince1970.isFinite else { return 0 }
        let overlap = max(0, min(end, localEnd).timeIntervalSince(max(start, localStart)))
        return overlap / max(1, max(end.timeIntervalSince(start), localEnd.timeIntervalSince(localStart)))
    }
}

@MainActor final class WorkoutReader {
    static var buildEnabled: Bool {
        #if GYMREST_HEALTHKIT
        true
        #else
        false
        #endif
    }
    #if GYMREST_HEALTHKIT
    private let health = HKHealthStore()
    #endif
    func candidates(start: Date, end: Date) async throws -> [WorkoutCandidate] {
        #if GYMREST_HEALTHKIT
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthFailure.unavailable }
        let runner = WorkoutQueryRunner(authorize: {
            try await self.health.requestAuthorization(toShare: [], read: [HKObjectType.workoutType()])
        }, fetch: { interval in
            let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: [])
            let result: [WorkoutCandidate] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit,
                    sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                    if let error { continuation.resume(throwing: error); return }
                    let candidates = (samples as? [HKWorkout] ?? []).map { workout in
                        let title: String
                        switch workout.workoutActivityType {
                        case .traditionalStrengthTraining: title = "传统力量训练"
                        case .functionalStrengthTraining: title = "功能性力量训练"
                        case .running: title = "跑步"
                        case .cycling: title = "骑行"
                        default: title = "运动记录"
                        }
                        return WorkoutCandidate(id: workout.uuid, start: workout.startDate, end: workout.endDate,
                            title: title, source: workout.sourceRevision.source.name, device: workout.device?.model)
                    }
                    continuation.resume(returning: candidates)
                }
                self.health.execute(query)
            }
            return result
        })
        return try await runner.candidates(start: start, end: end)
        #else
        throw HealthFailure.buildDisabled
        #endif
    }
}
enum HealthFailure: LocalizedError {
    case unavailable, buildDisabled, invalidInterval
    var errorDescription: String? {
        switch self {
        case .invalidInterval: "训练开始/结束时间不合法，无法查询健康运动。"
        case .unavailable: "此设备当前无法访问健康数据。"
        case .buildDisabled: "当前构建未启用 HealthKit。训练记录可独立使用；启用健康数据版本需要支持 HealthKit 的签名配置。"
        }
    }
}
