import Foundation
import Observation
@preconcurrency import WatchConnectivity
#if GYMREST_HEALTHKIT
@preconcurrency import HealthKit
#endif

@MainActor @Observable final class PhoneWatchLink: NSObject {
    static let shared = PhoneWatchLink()
    private struct Journal: Codable {
        var training: PhoneTrainingSnapshot?
        var start: WatchStartRequest?
        var latest: WatchWorkoutStatus?
        var receipts: [WatchWorkoutStatus] = []
        var ended: [String: Date] = [:]
        var pendingEnds: [String: WatchCommand] = [:]
        var sequence = 0
        var linkedReceiptIDs: [String]? = nil
    }
    private var journal = Journal()
    private let url: URL
    private var activated = false
    private var journalWritable = true
    private(set) var reachable = false
    private(set) var paired = false
    private(set) var installed = false
    private(set) var busy = false
    private(set) var issue: String?
    private(set) var latest: WatchWorkoutStatus?
    private(set) var confirmedThisLaunch = false
    private(set) var pendingStart: WatchStartRequest?
    var ensureRuntime: (@MainActor () throws -> Void)?
    var refreshTraining: (@MainActor () async -> Void)?
    var canStartRecording: (@MainActor (UUID) -> Bool)?
    var handleTrainingAction: (@MainActor (UUID, UUID, String) async -> String?)?
    var trainingEnd: (@MainActor (UUID) throws -> Date?)?
    var attachReceipt: (@MainActor (WatchWorkoutStatus) throws -> Bool)?
    #if GYMREST_HEALTHKIT
    private let health = HKHealthStore()
    private var mirrored: HKWorkoutSession?
    #endif
    static var buildEnabled: Bool {
        #if GYMREST_HEALTHKIT && GYMREST_WATCH
        true
        #else
        false
        #endif
    }
    override init() {
        url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WatchLink.json")
        super.init()
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                guard data.count <= 1024 * 1024 else { throw CompanionFailure.invalid }
                let loaded = try JSONDecoder().decode(Journal.self, from: data)
                guard (0...9_000_000_000_000_000).contains(loaded.sequence), loaded.receipts.count <= 50, loaded.ended.count <= 100, loaded.pendingEnds.count <= 100 else { throw CompanionFailure.invalid }
                try loaded.latest?.validate(); try loaded.training?.validate(); try loaded.start?.validate()
                for receipt in loaded.receipts { try receipt.validate() }
                for command in loaded.pendingEnds.values { try command.validate() }
                journal = loaded; latest = loaded.latest; pendingStart = loaded.start
            }
        } catch {
            journal = Journal()
            do { try FileManager.default.copyItem(at: url, to: url.deletingLastPathComponent().appendingPathComponent("WatchLink-corrupt-" + UUID().uuidString + ".json")) }
            catch { journalWritable = false }
            issue = "配对缓存暂时无法读取，请打开手表GymRest刷新；训练计划和记录未改动。"
        }
    }
    func activate() {
        guard !activated else { return }; activated = true
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
        #if GYMREST_HEALTHKIT
        // Register at app launch so HealthKit can wake this app to receive mirroring.
        health.workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor in
                self?.mirrored = session; session.delegate = self
            }
        }
        #endif
    }
    private func persist() throws {
        guard journalWritable else { throw CompanionFailure.invalidMessage("配对缓存需要保留并检查，暂不能覆盖。") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(journal).write(to: url, options: .atomic)
    }
    private func packet() -> CompanionPacket {
        let start = journal.start.flatMap { $0.isFresh(at: Date()) ? $0 : nil }
        return CompanionPacket(training: journal.training, startRequest: start)
    }
    private func updateContext() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        do { try WCSession.default.updateApplicationContext(["gymrest": packet().encoded()]) }
        catch { issue = "训练快照尚未同步：" + error.localizedDescription }
    }
    func publish(_ session: TrainingSession?) {
        activate()
        let previousID = journal.training?.trainingID
        if let session, session.phase != .completed, let id = session.sessionID, let token = session.interactionID {
            journal.sequence += 1
            journal.training = PhoneTrainingSnapshot(trainingID: id, interactionID: token, sequence: journal.sequence, sentAt: Date(),
                plan: session.planName, exercise: session.current.name, currentSet: session.completed[session.index], sets: session.current.sets,
                completedSets: session.completedSets, totalSets: session.totalSets, phase: session.phase.rawValue,
                part: session.partTitle, completionTitle: session.completionTitle, values: session.currentSetValues.summary,
                durationSeconds: session.currentSetValues.durationSeconds, effortStatus: session.effortTimer?.status.rawValue,
                effortRegistered: session.effortTimer?.registered ?? false, effortEnd: session.effortTimer?.end,
                restEnd: session.restEnd, remaining: Int(ceil(session.effortTimer?.remaining ?? session.remaining)), reminderRegistered: session.reminderRegistered)
            if journal.start?.trainingID != id { journal.start = nil; pendingStart = nil }
        } else { journal.training = nil; journal.start = nil; pendingStart = nil }
        if let previousID, journal.training?.trainingID != previousID {
            journal.ended[previousID.uuidString] = (try? trainingEnd?(previousID)) ?? Date()
            if journal.ended.count > 100 {
                journal.ended = Dictionary(uniqueKeysWithValues: journal.ended.sorted { $0.value > $1.value }.prefix(100).map { ($0.key, $0.value) })
            }
        }
        do { try persist() } catch { issue = "手表同步进度保存失败：" + error.localizedDescription }
        updateContext(); flushReceipts()
        if let latest { requestEndIfNeeded(latest) }
    }
    func startRecording(for session: TrainingSession) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            guard Self.buildEnabled else { throw CompanionFailure.invalidMessage("此安装包未启用Watch联动，请安装包含GymRest Watch的版本。") }
            guard session.phase != .completed, let id = session.sessionID else { throw CompanionFailure.wrongSession }
            guard paired, installed, WCSession.default.activationState == .activated else { throw CompanionFailure.unavailable }
            if let latest, !latest.phase.terminal { throw CompanionFailure.busy }
            await refreshTraining?()
            try makeStart(trainingID: id)
            #if GYMREST_HEALTHKIT
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .traditionalStrengthTraining; configuration.locationType = .indoor
            try await health.startWatchApp(toHandle: configuration)
            // A successful launch is not proof that a workout has started.
            #endif
            issue = nil
        } catch { issue = error.localizedDescription }
    }
    private func makeStart(trainingID: UUID) throws {
        guard Self.buildEnabled, canStartRecording?(trainingID) == true, let current = journal.training, current.trainingID == trainingID, current.phase != "completed", current.isFresh(at: Date()) else { throw CompanionFailure.wrongSession }
        if let latest, !latest.phase.terminal { throw CompanionFailure.busy }
        if (latest?.trainingID == trainingID && latest?.phase == .saved) || journal.receipts.contains(where: { $0.trainingID == trainingID && $0.phase == .saved }) {
            throw CompanionFailure.invalidMessage("本次手机训练已有保存的Watch记录，不重复开启；可继续计组，或结束后开始新训练。")
        }
        let now = Date()
        let request = WatchStartRequest(id: UUID(), trainingID: trainingID, createdAt: now, expiresAt: now.addingTimeInterval(120), title: current.plan)
        journal.start = request; pendingStart = request
        try persist(); updateContext()
    }
    func control(_ kind: WatchCommand.Kind) async {
        guard !busy, let latest, !latest.phase.terminal else { return }
        busy = true; defer { busy = false }
        do {
            let command = WatchCommand(kind: kind, trainingID: latest.trainingID, runID: latest.runID, requestedEnd: kind == .saveRecording ? Date() : nil, controlToken: latest.controlToken)
            try await send(command); issue = nil
        } catch { issue = error.localizedDescription }
    }
    private func send(_ command: WatchCommand) async throws {
        let data = try CompanionPacket(command: command).encoded()
        if WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isReachable {
            let response: Data = try await withCheckedThrowingContinuation { continuation in
                WCSession.default.sendMessageData(data, replyHandler: { continuation.resume(returning: $0) }, errorHandler: { continuation.resume(throwing: $0) })
            }
            try process(response)
        } else {
            #if GYMREST_HEALTHKIT
            guard let mirrored else { throw CompanionFailure.unavailable }
            try await mirrored.sendToRemoteWorkoutSession(data: data)
            #else
            throw CompanionFailure.unavailable
            #endif
        }
    }
    private func requestEndIfNeeded(_ status: WatchWorkoutStatus) {
        guard !status.phase.terminal, let ended = journal.ended[status.trainingID.uuidString] ?? (try? trainingEnd?(status.trainingID)), journal.pendingEnds[status.runID.uuidString] == nil else { return }
        let command = WatchCommand(kind: .saveRecording, trainingID: status.trainingID, runID: status.runID, requestedEnd: ended)
        journal.pendingEnds[status.runID.uuidString] = command
        do {
            try persist()
            // Saving one exact run is safe to deliver late; start and set actions are never queued.
            if WCSession.isSupported(), WCSession.default.activationState == .activated {
                WCSession.default.transferUserInfo(["gymrest": try CompanionPacket(command: command).encoded()])
            }
            Task {
                do { try await self.send(command) }
                catch {
                    if self.latest?.runID == status.runID, self.latest?.phase.terminal == false {
                        self.issue = "手机训练已结束，手表结束请求待确认；也可在手表手动结束。"
                    }
                }
            }
        } catch { issue = "手表结束请求尚未保存：" + error.localizedDescription }
    }
    func resetConnectionStatus() {
        // Explicit user confirmation only. This never stops or discards a Watch workout.
        journal.latest = nil; latest = nil; confirmedThisLaunch = false; journal.start = nil; pendingStart = nil
        do { try persist(); issue = nil; updateContext() } catch { issue = error.localizedDescription }
    }
    func refresh() async {
        activate(); refreshConnection()
        guard reachable else { return }
        do { try await send(WatchCommand(kind: .hello)) } catch { issue = error.localizedDescription }
        flushReceipts()
    }
    private func refreshConnection() {
        guard WCSession.isSupported() else { return }
        paired = WCSession.default.isPaired; installed = WCSession.default.isWatchAppInstalled
        reachable = WCSession.default.activationState == .activated && WCSession.default.isReachable
    }
    func flushReceipts() {
        guard let attachReceipt else { return }
        var pending: [WatchWorkoutStatus] = []
        for receipt in journal.receipts {
            do {
                if try !attachReceipt(receipt) { pending.append(receipt) }
                else if let id = receipt.workoutID?.uuidString {
                    journal.linkedReceiptIDs = Array(((journal.linkedReceiptIDs ?? []) + [id]).suffix(200))
                }
            }
            catch { pending.append(receipt); issue = "手表记录已保存，手机关联待重试：" + error.localizedDescription }
        }
        if pending != journal.receipts {
            journal.receipts = pending
            do { try persist() } catch { issue = error.localizedDescription }
        }
    }
    private func apply(_ status: WatchWorkoutStatus) throws {
        try status.validate()
        let known = journal.training?.trainingID == status.trainingID || journal.start?.trainingID == status.trainingID ||
            journal.ended[status.trainingID.uuidString] != nil || (try? trainingEnd?(status.trainingID)) != nil
        guard known else { throw CompanionFailure.wrongSession }
        if status.phase == .saved, !(journal.linkedReceiptIDs ?? []).contains(status.workoutID?.uuidString ?? ""), !journal.receipts.contains(where: { $0.workoutID == status.workoutID }) {
            journal.receipts.append(status); journal.receipts = Array(journal.receipts.suffix(50))
        }
        if status.supersedes(journal.latest) {
            if journal.latest?.runID != status.runID {
                // A newer own run proves previous runs are no longer active on this watch.
                journal.pendingEnds = journal.pendingEnds.filter { $0.key == status.runID.uuidString }
            }
            journal.latest = status; latest = status; confirmedThisLaunch = status.isFresh(at: Date())
            if status.phase != .starting, journal.start?.id == status.startRequestID { journal.start = nil; pendingStart = nil }
        }
        if status.phase.terminal { journal.pendingEnds[status.runID.uuidString] = nil }
        try persist(); flushReceipts(); requestEndIfNeeded(status)
    }
    private func process(_ data: Data) throws {
        try ensureRuntime?()
        let response = try CompanionPacket.decode(data)
        if let status = response.workout { try apply(status) }
        if let message = response.issue { throw CompanionFailure.invalidMessage(message) }
    }
    private func receive(_ data: Data) async {
        do { try process(data) } catch { issue = error.localizedDescription }
    }
    private func handle(_ data: Data) async -> Data {
        do {
            let request = try CompanionPacket.decode(data)
            try ensureRuntime?()
            await refreshTraining?()
            if let status = request.workout { try apply(status) }
            if let command = request.command {
                guard command.isFresh(at: Date()) else { throw CompanionFailure.expired }
                switch command.kind {
                case .hello: break
                case .requestRecording:
                    try makeStart(trainingID: command.trainingID!)
                case .trainingAction:
                    guard let current = journal.training, current.trainingID == command.trainingID,
                          current.interactionID == command.interactionID, let handleTrainingAction else { throw CompanionFailure.wrongSession }
                    if let message = await handleTrainingAction(current.trainingID, current.interactionID, command.action!) {
                        return try CompanionPacket(training: journal.training, issue: String(message.prefix(300))).encoded()
                    }
                default: throw CompanionFailure.invalid
                }
            }
            return try packet().encoded()
        } catch { return (try? CompanionPacket(issue: String(error.localizedDescription.prefix(300))).encoded()) ?? Data() }
    }
}

extension PhoneWatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let message = error?.localizedDescription
        Task { @MainActor in
            self.refreshConnection(); if let message { self.issue = message }
            self.updateContext()
            for command in self.journal.pendingEnds.values {
                if let data = try? CompanionPacket(command: command).encoded() { WCSession.default.transferUserInfo(["gymrest": data]) }
            }
        }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) { Task { @MainActor in self.refreshConnection() } }
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) { Task { @MainActor in self.refreshConnection() } }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) { Task { @MainActor in self.refreshConnection() } }
    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data, replyHandler: @escaping (Data) -> Void) {
        let reply = CompanionReply(send: replyHandler)
        Task { @MainActor in reply.send(await self.handle(messageData)) }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["gymrest"] as? Data else { return }
        Task { @MainActor in await self.receive(data) }
    }
}
#if GYMREST_HEALTHKIT
extension PhoneWatchLink: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let message = error.localizedDescription, identity = ObjectIdentifier(workoutSession)
        Task { @MainActor in
            guard let mirrored = self.mirrored, ObjectIdentifier(mirrored) == identity else { return }
            self.issue = "训练镜像暂时不可用：" + message
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in for item in data { await self.receive(item) } }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        let identity = ObjectIdentifier(workoutSession)
        Task { @MainActor in
            guard let mirrored = self.mirrored, ObjectIdentifier(mirrored) == identity else { return }
            self.mirrored = nil; self.issue = "手表镜像暂时断开；手表记录继续，重新连接后刷新。"
        }
    }
}
#endif
