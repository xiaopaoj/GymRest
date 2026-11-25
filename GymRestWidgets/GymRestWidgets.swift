import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

struct CountdownLabel: View {
    let state: AlarmPresentationState
    var body: some View {
        switch state.mode {
        case .countdown(let countdown):
            Text(timerInterval: countdown.startDate...max(countdown.startDate, countdown.fireDate), countsDown: true)
                .monospacedDigit().contentTransition(.identity)
        case .paused: Text("暂停")
        case .alert: Text("结束")
        @unknown default: Text("休息")
        }
    }
}

private struct RestSummary: View {
    let context: RestContext?
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(context?.exerciseName ?? "GymRest 组间休息").font(.headline).lineLimit(1)
            if let context {
                Text("已完成第 \(context.completedSet)/\(context.totalSets) 组 · \(context.planName)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else { Text("休息结束后开始下一组").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

@main
struct GymRestWidgets: WidgetBundle {
    var body: some Widget {
        TrainingLiveActivityWidget()
        RestLiveActivityWidget()
    }
}

struct RestLiveActivityWidget: Widget {
    private let returnURL = URL(string: "gymrest://training")!
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<RestMetadata>.self) { context in
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "timer").font(.title2).foregroundStyle(.orange)
                    RestSummary(context: context.attributes.metadata?.context)
                    Spacer(minLength: 8)
                    CountdownLabel(state: context.state)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(.orange).frame(width: 112).minimumScaleFactor(0.6)
                }
                if let next = context.attributes.metadata?.context?.nextStep {
                    Text(next).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(16).foregroundStyle(.white)
            .activityBackgroundTint(.black).activitySystemActionForegroundColor(.orange)
            .widgetURL(returnURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("休息", systemImage: "timer").font(.headline).foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CountdownLabel(state: context.state)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(.orange).frame(width: 110).minimumScaleFactor(0.6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        RestSummary(context: context.attributes.metadata?.context)
                        Text(context.attributes.metadata?.context?.nextStep ?? "点击返回 GymRest")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(.orange)
            } compactTrailing: {
                CountdownLabel(state: context.state).font(.caption.monospacedDigit())
                    .foregroundStyle(.orange).frame(width: 58).minimumScaleFactor(0.6)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(.orange)
            }
            .widgetURL(returnURL).keylineTint(.orange)
        }
    }
}
