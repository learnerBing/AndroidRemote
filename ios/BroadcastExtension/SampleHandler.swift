import ReplayKit

/// Broadcast Upload Extension entry — captures screen and streams via WebRTC.
class SampleHandler: RPBroadcastSampleHandler {

    private var signaling = SignalingClient()
    private var webRtcEngine: WebRtcBroadcastEngine?
    private var isStreaming = false
    private let audioSampleQueue = DispatchQueue(label: "com.androidremote.broadcast.audio")

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        ARLog.info("Broadcast", "broadcastStarted")
#if canImport(WebRTC)
        ReplayKitAudioDevice.shared.prepareForBroadcast()
#endif
        guard let snapshot = SessionStore.load() else {
            let container = SessionStore.appGroupContainerURL()?.path ?? "nil"
            ARLog.error("Broadcast", "no session in App Group (container=\(container)) — link receiver in app first")
            BroadcastNotification.postFailed()
            finishBroadcastWithError(NSError(
                domain: "AndroidRemote",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No linked session. Open AndroidRemote → Link Receiver → then start broadcast from the in-app button."]
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

        // Extension memory budget (~50 MB): use 720p profile, not full lanRelay 1080p.
        let streamConfig: StreamConfig = snapshot.transport == .directLanRelay
            ? .broadcastExtension
            : .castReceiver

        signaling = SignalingClient()
        signaling.bind(snapshot: snapshot)
        let engine = WebRtcBroadcastEngine(signaling: signaling, streamConfig: streamConfig)
        webRtcEngine = engine

        Task {
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { [weak self] in
                        guard let self, let engine = self.webRtcEngine else { return }
                        engine.onCaptureReady = { [weak self] in
                            ARLog.info("Broadcast", "video capture ready")
                            self?.isStreaming = true
                            BroadcastNotification.postStarted()
                        }
                        try await engine.start(session: snapshot)
                        try? await signaling.updateSessionStatus(sessionId: snapshot.sessionId, state: "broadcasting")
                        ARLog.info("Broadcast", "WebRTC start completed session=\(ARLog.sessionPrefix(snapshot.sessionId))")
                    }
                    group.addTask {
                        try await Task.sleep(nanoseconds: 90_000_000_000)
                        throw CastError.answerTimeout
                    }
                    try await group.next()
                    group.cancelAll()
                }
            } catch let error as CastError {
                ARLog.error("Broadcast", "failed CastError=\(error.localizedDescription) relay=\(snapshot.signalingHost):\(snapshot.signalingPort)")
                BroadcastNotification.postFailed()
                finishBroadcastWithError(NSError(
                    domain: "AndroidRemote",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "\(error.localizedDescription) (relay \(snapshot.signalingHost):\(snapshot.signalingPort))"]
                ))
            } catch {
                ARLog.error("Broadcast", "failed error=\(error.localizedDescription)")
                BroadcastNotification.postFailed()
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
        webRtcEngine?.stop()
        webRtcEngine = nil
#if canImport(WebRTC)
        ReplayKitAudioDevice.shared.terminateDevice()
#endif
        ARLog.clearRelay()
        BroadcastNotification.postFinished()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .video:
            guard isStreaming else { return }
            webRtcEngine?.pushVideoSample(sampleBuffer)
        case .audioApp:
            guard isStreaming else { return }
            audioSampleQueue.async { [weak self, sampleBuffer] in
                self?.webRtcEngine?.pushAppAudioSample(sampleBuffer)
            }
        case .audioMic:
            guard isStreaming else { return }
            audioSampleQueue.async { [weak self, sampleBuffer] in
                self?.webRtcEngine?.pushMicAudioSample(sampleBuffer)
            }
        @unknown default:
            break
        }
    }
}
