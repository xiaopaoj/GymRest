import Foundation

/// A delayed Health sample is evidence of recent activity, never proof that
/// Apple's Workout app (or another app) is currently recording.
struct ExerciseActivitySample: Sendable, Equatable {
    let id: UUID
    let start: Date
    let end: Date
    let minutes: Double
    let productType: String?
    var userEntered = false
}

struct ExerciseActivityEvidence: Sendable, Equatable {
    enum Kind: Sendable, Equatable { case recentActivity, olderActivity, unknownSource, noData }
    let kind: Kind
    let latestSampleEnd: Date?
    static let lookback: TimeInterval = 15 * 60
    static let freshness: TimeInterval = 3 * 60

    static func analyze(_ samples: [ExerciseActivitySample], at now: Date) -> Self {
        let valid = samples.filter { sample in
            let span = sample.end.timeIntervalSince(sample.start)
            return now.timeIntervalSince1970.isFinite && sample.start.timeIntervalSince1970.isFinite &&
                sample.end.timeIntervalSince1970.isFinite && !sample.userEntered &&
                sample.minutes.isFinite && sample.minutes > 0 && span > 0 && span <= 5 * 60 &&
                sample.minutes <= span / 60 + 0.01 && sample.start >= now.addingTimeInterval(-lookback) && sample.end <= now
        }
        // Missing source information is unknown, not evidence from a Watch.
        let watch = valid.filter { $0.productType?.hasPrefix("Watch") == true }
        if let latest = watch.map(\.end).max() {
            return Self(kind: now.timeIntervalSince(latest) <= freshness ? .recentActivity : .olderActivity, latestSampleEnd: latest)
        }
        if let latest = valid.map(\.end).max() { return Self(kind: .unknownSource, latestSampleEnd: latest) }
        return Self(kind: .noData, latestSampleEnd: nil)
    }

    var title: String {
        switch kind {
        case .recentActivity: "近期有手表运动迹象 · 运动模式未确认"
        case .olderActivity: "健康数据较旧 · 当前状态无法判断"
        case .unknownSource: "已读取运动数据 · 手表来源未确认"
        case .noData: "未拉取到近期健康数据 · 暂无法判断"
        }
    }
}
