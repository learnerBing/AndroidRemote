import ReplayKit

/// Broadcast Upload Extension entry — captures screen and streams via WebRTC.
class SampleHandler: RPBroadcastSampleHandler {

    private let signaling = SignalingClient()
    private lazy var webRtcEngine = WebRtcBroadcastEngine(signaling: signaling)
    private var isStreaming = false

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard let snapshot = SessionStore.load() else {
            finishBroadcastWithError(NSError(
                domain: "AndroidRemote",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No paired session. Pair from the iPhone app first."]
            ))
            return
        }

        Task {
            do {
                try await webRtcEngine.start(session: snapshot)
                isStreaming = true
            } catch {
                finishBroadcastWithError(error as NSError)
            }
        }
    }

    override func broadcastPaused() {}

    override func broadcastResumed() {}

    override func broadcastFinished() {
        isStreaming = false
        webRtcEngine.stop()
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
