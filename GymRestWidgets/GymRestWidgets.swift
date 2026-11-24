import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

struct CountdownLabel: View {
    let state: AlarmPresentationState
    var body: some View {
        switch state.mode {
        case .countdown(let countdown):
            Text(timerInterval: countdown.startDate...countdown.fireDate, countsDown: true).monospacedDigit()
        case .paused: Text("已暂停")
        case .alert: Text("休息结束")
        @unknown default: Text("休息")
        }
    }
}

@main
struct GymRestWidgets: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<RestMetadata>.self) { context in
            HStack {
                Image(systemName: "timer")
                Text("GymRest · 组间休息")
                Spacer()
                CountdownLabel(state: context.state).font(.title2.bold())
            }.padding().activityBackgroundTint(.black).activitySystemActionForegroundColor(.orange)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label("休息", systemImage: "timer") }
                DynamicIslandExpandedRegion(.trailing) { CountdownLabel(state: context.state) }
                DynamicIslandExpandedRegion(.bottom) { Text("GymRest · 休息结束后开始下一组") }
            } compactLeading: { Image(systemName: "timer") }
              compactTrailing: { CountdownLabel(state: context.state).frame(maxWidth: 64) }
              minimal: { Image(systemName: "timer") }
              .keylineTint(.orange)
        }
    }
}
