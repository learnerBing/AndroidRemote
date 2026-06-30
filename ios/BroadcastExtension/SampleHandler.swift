import ReplayKit

/// Broadcast Upload Extension entry — captures screen and streams via WebRTC.
class SampleHandler: RPBroadcastSampleHandler {

    private let signaling = SignalingClient()
    private lazy var webRtcEngine = WebRtcBroadcastEngine(signaling: signaling)
    private var isStreaming = false

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        ARLog.info("Broadcast", "broadcastStarted")
        guard let snapshot = SessionStore.load() else {
            ARLog.error("Broadcast", "no session in App Group — link receiver in Test tab first")
            finishBroadcastWithError(NSError(
                domain: "AndroidRemote",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No linked session. Tap Link Receiver in the Test tab, then start broadcast."]
            ))
            return
        }

        ARLog.info(
            "Broadcast",
            "session=\(ARLog.sessionPrefix(snapshot.sessionId)) relay=\(snapshot.signalingHost):\(snapshot.signalingPort) transport=\(snapshot.transport.rawValue)"
        )
        ARLog.configureRelay(
            host: snapshot.signalingHost,
            port: snapshot.signalingPort,
            sessionId: snapshot.sessionId
        )

        Task {
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { [weak self] in
                        guard let self else { return }
                        self.webRtcEngine.onCaptureReady = { [weak self] in
                            ARLog.info("Broadcast", "video capture ready")
                            self?.isStreaming = true
                        }
                        try await self.webRtcEngine.start(session: snapshot)
                        ARLog.info("Broadcast", "WebRTC start completed session=\(ARLog.sessionPrefix(snapshot.sessionId))")
                    }
                    group.addTask {
                        try await Task.sleep(nanoseconds: 60_000_000_000)
                        throw CastError.answerTimeout
                    }
                    try await group.next()
                    group.cancelAll()
                }
            } catch let error as CastError {
                ARLog.error("Broadcast", "failed CastError=\(error.localizedDescription) relay=\(snapshot.signalingHost):\(snapshot.signalingPort)")
                finishBroadcastWithError(NSError(
                    domain: "AndroidRemote",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "\(error.localizedDescription) (relay \(snapshot.signalingHost):\(snapshot.signalingPort))"]
                ))
            } catch {
                ARLog.error("Broadcast", "failed error=\(error.localizedDescription)")
                finishBroadcastWithError(NSError(
                    domain: "AndroidRemote",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Broadcast failed: \(error.localizedDescription)"]
                ))
            }
        }
    }

    override func broadcastPaused() {}

    override func broadcastResumed() {}

    override func broadcastFinished() {
        ARLog.info("Broadcast", "broadcastFinished")
        isStreaming = false
        webRtcEngine.stop()
        ARLog.clearRelay()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard isStreaming else { return }
        switch sampleBufferType {
        case .video:
            webRtcEngine.pushVideoSample(sampleBuffer)
        case .audioApp, .audioMic:
            break // Phase 3: audio pipeline
        @unknown default:
            break
        }
    }
}
