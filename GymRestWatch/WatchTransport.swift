import Foundation
import Observation
@preconcurrency import WatchConnectivity

@MainActor @Observable final class WatchTransport: NSObject, WCSessionDelegate {
    private(set) var reachable = false
    private(set) var activated = false
    var receive: (@MainActor (Data) async -> Data)?
    func activate() { WCSession.default.delegate = self; WCSession.default.activate() }
    func request(_ packet: CompanionPacket) async throws -> CompanionPacket {
        guard activated, WCSession.default.isReachable else { throw CompanionFailure.unavailable }
        let data = try packet.encoded()
        let reply: Data = try await withCheckedThrowingContinuation { continuation in
            WCSession.default.sendMessageData(data, replyHandler: { continuation.resume(returning: $0) }, errorHandler: { continuation.resume(throwing: $0) })
        }
        let result = try CompanionPacket.decode(reply)
        if let issue = result.issue { throw CompanionFailure.invalidMessage(issue) }
        return result
    }
    func publish(_ packet: CompanionPacket, durable: Bool) {
        guard activated, let data = try? packet.encoded() else { return }
        try? WCSession.default.updateApplicationContext(["gymrest": data])
        if durable { WCSession.default.transferUserInfo(["gymrest": data]) }
        if WCSession.default.isReachable {
            WCSession.default.sendMessageData(data, replyHandler: { [weak self] reply in
                Task { @MainActor in _ = await self?.receive?(reply) }
            }, errorHandler: { _ in })
        }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let active = activationState == .activated, reachable = session.isReachable
        let context = session.receivedApplicationContext["gymrest"] as? Data
        Task { @MainActor in
            self.activated = active; self.reachable = reachable
            if let context { _ = await self.receive?(context) }
        }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.reachable = reachable }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data, replyHandler: @escaping (Data) -> Void) {
        let reply = CompanionReply(send: replyHandler)
        Task { @MainActor in reply.send(await self.receive?(messageData) ?? Data()) }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["gymrest"] as? Data else { return }
        Task { @MainActor in _ = await self.receive?(data) }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["gymrest"] as? Data else { return }
        Task { @MainActor in _ = await self.receive?(data) }
    }
}
