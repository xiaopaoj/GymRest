import Foundation
import Observation
@preconcurrency import HealthKit

@MainActor @Observable final class WatchWorkoutManager: NSObject {
    static let shared = WatchWorkoutManager()
    static let runKey = "dev.gymrest.watch.runID"
    static let trainingKey = "dev.gymrest.training.sessionID"
    private struct Journal: Codable {
        let trainingID: UUID
        let runID: UUID
        var phase: WatchWorkoutStatus.Phase
        var sequence = 0
        var start: Date?
        var end: Date?
        var workoutID: UUID?
        var collectionEnded = false
        var discard = false
        var controlToken: UUID? = UUID()
        var startRequestID: UUID? = nil
    }
    let transport = WatchTransport()
    private let health = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var journal: Journal?
    private let url: URL
    private var heartbeat: Task<Void, Never>?
    private var finishing = false
    private var starting = false
    private var pendingFinish: (save: Bool, end: Date?)?
    private var journalWritable = true
    private(set) var phone: PhoneTrainingSnapshot?
    private(set) var startRequest: WatchStartRequest?
    private(set) var status: WatchWorkoutStatus?
    private(set) var heartRate: Double?
    private(set) var energy: Double?
    private(set) var issue: String?
    private(set) var busy = false
    private(set) var unlinkedRecovery = false
    var needsRecovery: Bool { journal?.phase.terminal == false && session == nil }
    var canStart: Bool { session == nil && (journal == nil || journal?.phase.terminal == true) }
    override init() {
        url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("GymRestWorkout.json")
        super.init()
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                guard data.count <= 65536 else { throw CompanionFailure.invalid }
                journal = try JSONDecoder().decode(Journal.self, from: data)
                status = makeStatus()
            }
        } catch { issue = "手表记录缓存无法读取，请先尝试恢复，暂不开始新记录。"; unlinkedRecovery = true; journalWritable = false }
        transport.receive = { [weak self] data in await self?.receive(data) ?? Data() }
        transport.activate()
    }
    private func persist() throws {
        guard journalWritable else { throw CompanionFailure.invalidMessage("手表缓存需要先恢复或明确清除，当前未覆盖原文件。") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let journal else {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            return
        }
        try JSONEncoder().encode(journal).write(to: url, options: .atomic)
    }
    private func setPhase(_ phase: WatchWorkoutStatus.Phase) {
        if journal?.phase != phase { journal?.controlToken = UUID() }
        journal?.phase = phase
    }
    private func makeStatus() -> WatchWorkoutStatus? {
        guard let value = journal, value.phase.terminal || session != nil else { return nil }
        return WatchWorkoutStatus(trainingID: value.trainingID, runID: value.runID, sequence: max(1, value.sequence), phase: value.phase,
            sentAt: Date(), start: value.start, end: value.end, workoutID: value.workoutID,
            heartRate: heartRate, activeEnergy: energy, issue: issue.map { String($0.prefix(300)) }, controlToken: value.controlToken, startRequestID: value.startRequestID)
    }
    private func push(durable: Bool = false) {
        journal?.sequence += 1; status = makeStatus()
        do { try persist() } catch { issue = "手表状态保存失败：" + error.localizedDescription }
        guard let status else { return }
        let packet = CompanionPacket(workout: status)
        transport.publish(packet, durable: durable)
        if let session, !status.phase.terminal, let data = try? packet.encoded() {
            Task { try? await session.sendToRemoteWorkoutSession(data: data) }
        }
    }
    private func applyPhone(_ packet: CompanionPacket) {
        if let incoming = packet.training {
            if incoming.trainingID != phone?.trainingID || incoming.sequence >= (phone?.sequence ?? 0) { phone = incoming }
        } else if packet.command == nil && packet.workout == nil { phone = nil }
        if let request = packet.startRequest, request.isFresh(at: Date()), request.trainingID == phone?.trainingID { startRequest = request }
        else if packet.command == nil { startRequest = nil }
    }
    func refresh() async {
        do {
            let response = try await transport.request(CompanionPacket(command: WatchCommand(kind: .hello)))
            applyPhone(response)
            if let journal, !journal.phase.terminal, session == nil { await recover() }
            else { push(durable: journal?.phase == .saved) }
        } catch { issue = error.localizedDescription }
    }
    func requestRecording() async {
        guard let phone else { issue = "请先在iPhone开始一场GymRest训练。"; return }
        do {
            let response = try await transport.request(CompanionPacket(command: WatchCommand(kind: .requestRecording, trainingID: phone.trainingID)))
            applyPhone(response); issue = nil
        } catch { issue = error.localizedDescription }
    }
    func startPending() async {
        guard !busy, canStart, !unlinkedRecovery else { return }
        busy = true; starting = true
        defer {
            busy = false; starting = false
            if let pending = pendingFinish {
                pendingFinish = nil
                Task { await self.finish(save: pending.save, requestedEnd: pending.end) }
            }
        }
        var createdInThisCall: HKWorkoutSession?
        do {
            guard let request = startRequest, request.isFresh(at: Date()) else { throw CompanionFailure.expired }
            guard HKHealthStore.isHealthDataAvailable() else { throw CompanionFailure.unavailable }
            let workout = HKObjectType.workoutType(), heart = HKQuantityType(.heartRate), energy = HKQuantityType(.activeEnergyBurned)
            try await health.requestAuthorization(toShare: [workout, energy], read: [workout, heart, energy])
            guard health.authorizationStatus(for: workout) == .sharingAuthorized else { throw CompanionFailure.invalidMessage("请在手表设置中允许GymRest写入训练记录。") }
            // Authorization may have taken minutes. Recheck the live phone request before creating a session.
            let response = try await transport.request(CompanionPacket(command: WatchCommand(kind: .hello)))
            applyPhone(response)
            guard response.startRequest?.id == request.id, request.isFresh(at: Date()), response.training?.trainingID == request.trainingID else { throw CompanionFailure.expired }
            let configuration = HKWorkoutConfiguration(); configuration.activityType = .traditionalStrengthTraining; configuration.locationType = .indoor
            let created = try HKWorkoutSession(healthStore: health, configuration: configuration)
            createdInThisCall = created
            let createdBuilder = created.associatedWorkoutBuilder()
            session = created; builder = createdBuilder
            created.delegate = self; createdBuilder.delegate = self
            createdBuilder.dataSource = HKLiveWorkoutDataSource(healthStore: health, workoutConfiguration: configuration)
            let date = Date()
            journal = Journal(trainingID: request.trainingID, runID: UUID(), phase: .starting, start: date, startRequestID: request.id)
            try persist()
            try await createdBuilder.addMetadata([Self.runKey: journal!.runID.uuidString, Self.trainingKey: request.trainingID.uuidString])
            do { try await created.startMirroringToCompanionDevice() }
            catch { issue = "镜像尚未连接；手表将继续记录，可稍后刷新手机。" }
            guard session === created, created.state != .ended, phone?.trainingID == request.trainingID, request.isFresh(at: Date()) else { throw CompanionFailure.busy }
            created.startActivity(with: date)
            try await createdBuilder.beginCollection(at: date)
            startRequest = nil
            startHeartbeat(); push()
        } catch {
            issue = error.localizedDescription
            if let createdInThisCall, session === createdInThisCall {
                createdInThisCall.end(); builder?.discardWorkout(); self.session = nil; builder = nil; setPhase(.failed); push(durable: true)
            }
        }
    }
    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { break }
                guard let self, self.session != nil, self.journal?.phase.terminal == false else { break }
                self.push()
            }
        }
    }
    func pause() { guard !starting, session?.state == .running else { return }; session?.pause() }
    func resume() { guard !starting, session?.state == .paused else { return }; session?.resume() }
    func finish(save: Bool, requestedEnd: Date? = nil) async {
        if starting { pendingFinish = (save, requestedEnd); return }
        guard !finishing, let session, let builder, journal?.phase.terminal == false else { return }
        finishing = true; busy = true; defer { finishing = false; busy = false }
        do {
            if let existing = try await findSaved() { completed(existing); session.end(); return }
            let start = journal?.start ?? Date()
            let end = max(start, min(requestedEnd ?? journal?.end ?? Date(), Date()))
            journal?.end = end; setPhase(.ending); journal?.discard = !save
            try persist(); push()
            if session.state != .stopped && session.state != .ended { session.stopActivity(with: end) }
            if !save {
                builder.discardWorkout(); session.end(); setPhase(.discarded); self.session = nil; self.builder = nil
                heartbeat?.cancel(); issue = nil; push(durable: true); return
            }
            if journal?.collectionEnded != true {
                try await builder.endCollection(at: end)
                journal?.collectionEnded = true; try persist()
            }
            guard let workout = try await builder.finishWorkout() else { throw CompanionFailure.invalidMessage("系统没有返回已保存训练，请重试或在健康App核对。") }
            completed(workout); session.end()
        } catch {
            // Retain the journal and builder for retry. Never manufacture a second workout.
            issue = "保存未确认，请重试：" + error.localizedDescription
            push()
        }
    }
    private func completed(_ workout: HKWorkout) {
        setPhase(.saved); journal?.workoutID = workout.uuid; journal?.start = workout.startDate; journal?.end = workout.endDate
        issue = nil; session = nil; builder = nil; heartbeat?.cancel(); push(durable: true)
    }
    private func findSaved() async throws -> HKWorkout? {
        guard let runID = journal?.runID else { return nil }
        let predicate = HKQuery.predicateForObjects(withMetadataKey: Self.runKey, allowedValues: [runID.uuidString])
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: (samples as? [HKWorkout])?.first) }
            }
            health.execute(query)
        }
    }
    func recover() async {
        guard !busy, session == nil else { return }; busy = true
        do {
            if let existing = try await findSaved() {
                // A crash may occur after HealthKit saved but before end() returned.
                let leftover = try? await health.recoverActiveWorkoutSession()
                leftover?.end(); completed(existing); busy = false; return
            }
            let recovered = try await health.recoverActiveWorkoutSession()
            guard let recovered else { unlinkedRecovery = true; throw CompanionFailure.invalidMessage("没有可恢复的活动记录。若之前正在保存，请先在健康App核对；GymRest不会补造或重复保存训练。") }
            session = recovered; builder = recovered.associatedWorkoutBuilder()
            recovered.delegate = self; builder?.delegate = self
            guard journal != nil else { unlinkedRecovery = true; throw CompanionFailure.wrongSession }
            let ending = journal?.phase == .ending || recovered.state == .stopped || recovered.state == .ended
            if ending { setPhase(.ending); journal?.end = journal?.end ?? recovered.endDate ?? Date() }
            if !ending { setPhase(recovered.state == .paused ? .paused : .running) }
            issue = nil; startHeartbeat()
            try? await recovered.startMirroringToCompanionDevice()
            push(); busy = false
            if ending { await finish(save: journal?.discard != true, requestedEnd: journal?.end) }
        } catch { issue = error.localizedDescription; busy = false }
    }
    func discardUnlinkedRecovery() {
        guard unlinkedRecovery else { return }
        builder?.discardWorkout(); session?.end(); self.session = nil; builder = nil; unlinkedRecovery = false
        let validJournal = journalWritable && journal != nil
        journalWritable = true
        issue = "无法关联的活动记录或缓存已清除；已保存的健康记录未删除。"
        if validJournal { setPhase(.discarded); push(durable: true) }
        else { journal = nil; try? persist() }
    }
    func trainingAction(_ action: String) async {
        guard !busy, let phone, phone.isFresh(at: Date()) else { issue = "训练快照已过期，请先刷新手机连接。"; return }
        busy = true; defer { busy = false }
        do {
            let command = WatchCommand(kind: .trainingAction, trainingID: phone.trainingID, interactionID: phone.interactionID, action: action)
            let response = try await transport.request(CompanionPacket(command: command)); applyPhone(response); issue = nil
        } catch { issue = error.localizedDescription }
    }
    private func receive(_ data: Data) async -> Data {
        do {
            let packet = try CompanionPacket.decode(data); applyPhone(packet)
            if let command = packet.command {
                guard command.isFresh(at: Date()) else { throw CompanionFailure.expired }
                if command.kind != .hello {
                    guard let status = makeStatus(), command.targets(status, at: Date()) else { throw CompanionFailure.wrongSession }
                    switch command.kind {
                    case .pauseRecording: pause()
                    case .resumeRecording: resume()
                    case .saveRecording: await finish(save: true, requestedEnd: command.requestedEnd)
                    case .discardRecording: await finish(save: false)
                    default: throw CompanionFailure.invalid
                    }
                }
            }
            journal?.sequence += 1; status = makeStatus(); try persist()
            return try CompanionPacket(workout: status).encoded()
        } catch { return (try? CompanionPacket(issue: String(error.localizedDescription.prefix(300))).encoded()) ?? Data() }
    }
}

extension WatchWorkoutManager: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        let identity = ObjectIdentifier(workoutSession)
        Task { @MainActor in
            guard let session = self.session, ObjectIdentifier(session) == identity else { return }
            if !self.finishing && toState == .running { self.setPhase(.running) }
            else if !self.finishing && toState == .paused { self.setPhase(.paused) }
            else if (toState == .ended || toState == .stopped) && !self.finishing && self.journal?.phase.terminal == false {
                await self.finish(save: true, requestedEnd: date); return
            }
            self.push()
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let identity = ObjectIdentifier(workoutSession), message = error.localizedDescription
        Task { @MainActor in
            guard let session = self.session, ObjectIdentifier(session) == identity else { return }
            self.issue = message
            await self.finish(save: true)
        }
    }
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let identity = ObjectIdentifier(workoutBuilder)
        Task { @MainActor in
            guard let builder = self.builder, ObjectIdentifier(builder) == identity else { return }
            let heart = builder.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            let energy = builder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
            self.heartRate = heart.flatMap { $0.isFinite && (0...400).contains($0) ? $0 : nil }
            self.energy = energy.flatMap { $0.isFinite && (0...100000).contains($0) ? $0 : nil }
            self.push()
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in for item in data { _ = await self.receive(item) } }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        let identity = ObjectIdentifier(workoutSession)
        Task { @MainActor in
            guard let session = self.session, ObjectIdentifier(session) == identity else { return }
            self.issue = "手机镜像暂时断开，手表继续记录；可在这里手动结束。"
        }
    }
}
