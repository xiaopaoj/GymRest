import Foundation
import Observation

@MainActor @Observable
final class ProbeModel {
    private let alarm: any TimerService
    private let notification: any TimerService
    private let defaults: UserDefaults
    private let key = "GymRest.probe.task"
    var task: RestTask?
    var useNotification = false
    var busy = false
    var permission = "尚未查询"
    var systemStatus = "无任务"
    var error: String?
    var service: any TimerService { useNotification ? notification : alarm }
    init(alarm: any TimerService = AlarmKitTimerService(), notification: any TimerService = LocalNotificationTimerService(), defaults: UserDefaults = .standard) {
        self.alarm = alarm; self.notification = notification; self.defaults = defaults
        if let data = defaults.data(forKey: key) { task = try? JSONDecoder().decode(RestTask.self, from: data) }
        useNotification = task?.backend == "notification"
    }
    private func backend(for task: RestTask) -> any TimerService { task.backend == "alarm" ? alarm : notification }
    func authorize() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { try await service.authorize(); error = nil } catch { self.error = String(reflecting: error) + "\n" + error.localizedDescription }
        await refresh()
    }
    func refresh() async {
        permission = await service.authorization
        guard let task else { systemStatus = "无任务"; return }
        do { systemStatus = try await backend(for: task).status(id: task.id) }
        catch { self.error = String(reflecting: error) + "\n" + error.localizedDescription }
    }
    func start(seconds: Int) async {
        guard !busy else { return }
        guard (1...86400).contains(seconds) else { error = TimerFailure.invalidDuration.localizedDescription; return }
        busy = true; defer { busy = false }
        do {
            if let task { try await backend(for: task).cancel(id: task.id) }
            let next = RestTask(id: UUID(), end: Date().addingTimeInterval(Double(seconds)), backend: useNotification ? "notification" : "alarm")
            // Save the identifier before scheduling, so a process interruption remains recoverable.
            defaults.set(try JSONEncoder().encode(next), forKey: key); task = next
            try await service.start(id: next.id, seconds: seconds)
            error = nil
        } catch { self.error = String(reflecting: error) + "\n" + error.localizedDescription }
        await refresh()
    }
    func cancel() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            if let task { try await backend(for: task).cancel(id: task.id) }
            task = nil; defaults.removeObject(forKey: key); error = nil
        } catch { self.error = String(reflecting: error) + "\n" + error.localizedDescription }
        await refresh()
    }
}
