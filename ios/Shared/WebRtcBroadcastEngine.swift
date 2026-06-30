import Foundation
import AVFoundation

#if canImport(WebRTC)
import WebRTC
#endif

#if canImport(WebRTC)
private final class FramePusher: RTCVideoCapturer {}
#endif

/// WebRTC sender used by the Broadcast Upload Extension (offerer role).
/// Link GoogleWebRTC via SPM to enable real streaming.
final class WebRtcBroadcastEngine: NSObject, @unchecked Sendable {

    private let signaling: SignalingClient
    private let streamConfig: StreamConfig
    private let extensionSignalingServer = ExtensionSignalingServer()
    private var activeSessionId: String?

#if canImport(WebRTC)
    private var factory: RTCPeerConnectionFactory?
    private var peerConnection: RTCPeerConnection?
    private var videoSource: RTCVideoSource?
    private var videoCapturer: RTCVideoCapturer?
    private var localIceCandidates: [IceCandidate] = []
    private var icePollTask: Task<Void, Never>?
    private var iceRepublishTask: Task<Void, Never>?
    private var offerSent = false
    private var iceGatheringContinuations: [CheckedContinuation<Void, Never>] = []
    private let factoryQueue = DispatchQueue(label: "com.androidremote.webrtc")
#endif

    /// Called once video capture pipeline is ready (before SDP exchange completes).
    var onCaptureReady: (() -> Void)?

    init(signaling: SignalingClient, streamConfig: StreamConfig = StreamConfig()) {
        self.signaling = signaling
        self.streamConfig = streamConfig
        super.init()
    }

    func start(session: SessionStore.Snapshot) async throws {
        signaling.bind(snapshot: session)
        activeSessionId = session.sessionId

        if session.transport == .castReceiver {
            extensionSignalingServer.registerSession(session.sessionId)
            do {
                try extensionSignalingServer.start()
            } catch {
                throw CastError.notConfigured
            }
        }
        // directLanRelay: Mac relay handles signaling; extension uses outbound HTTP only.

#if canImport(WebRTC)
        try await startWebRtc(sessionId: session.sessionId)
#else
        throw CastError.webRtcUnavailable
#endif
    }

    func stop() {
        let endingSession = activeSessionId
        extensionSignalingServer.stop()
        activeSessionId = nil
#if canImport(WebRTC)
        icePollTask?.cancel()
        icePollTask = nil
        iceRepublishTask?.cancel()
        iceRepublishTask = nil
        offerSent = false
        factoryQueue.sync {
            iceGatheringContinuations.removeAll()
            peerConnection?.close()
            peerConnection = nil
            videoSource = nil
            videoCapturer = nil
            factory = nil
            localIceCandidates.removeAll()
        }
        if let endingSession {
            Task {
                try? await signaling.updateSessionStatus(sessionId: endingSession, state: "ended")
            }
        }
#endif
    }

#if canImport(WebRTC)
    func pushVideoSample(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let capturer = videoCapturer,
              let source = videoSource else { return }

        let timestampNs = Int64(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            * Double(NSEC_PER_SEC))
        let rtcBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let rotation = frameRotation(from: sampleBuffer)
        let frame = RTCVideoFrame(buffer: rtcBuffer, rotation: rotation, timeStampNs: timestampNs)
        source.capturer(capturer, didCapture: frame)
    }

    private func startWebRtc(sessionId: String) async throws {
        try await runOnFactoryQueue {
            try self.setupPeerConnection()
        }

        let offer = try await createOffer()
        try await setLocalDescription(offer)
        await waitForIceGatheringComplete(timeoutSeconds: 8)

        let finalSdp = factoryQueue.sync {
            peerConnection?.localDescription?.sdp ?? offer.sdp
        }
        offerSent = true
        try await signaling.sendOffer(sessionId: sessionId, sdp: finalSdp)
        try await flushLocalIceCandidates(sessionId: sessionId)

        startOfferRefreshTask(sessionId: sessionId)
        startLocalIceRepublish(sessionId: sessionId)

        try await exchangeIce(sessionId: sessionId)
        startRemoteIcePolling(sessionId: sessionId)
    }

    private func runOnFactoryQueue(_ work: @escaping () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            factoryQueue.async {
                do {
                    try work()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func createOffer() async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RTCSessionDescription, Error>) in
            factoryQueue.async { [weak self] in
                guard let pc = self?.peerConnection else {
                    continuation.resume(throwing: CastError.notConfigured)
                    return
                }
                let constraints = RTCMediaConstraints(
                    mandatoryConstraints: [
                        "OfferToReceiveAudio": "false",
                        "OfferToReceiveVideo": "false",
                    ],
                    optionalConstraints: nil
                )
                pc.offer(for: constraints) { sdp, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let sdp else {
                        continuation.resume(throwing: CastError.notConfigured)
                        return
                    }
                    continuation.resume(returning: sdp)
                }
            }
        }
    }

    private func setLocalDescription(_ sdp: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            factoryQueue.async { [weak self] in
                guard let pc = self?.peerConnection else {
                    continuation.resume(throwing: CastError.notConfigured)
                    return
                }
                pc.setLocalDescription(sdp) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func startOfferRefreshTask(sessionId: String) {
        Task { [weak self] in
            guard let self else { return }
            await self.waitForIceGatheringComplete()
            let updated = self.factoryQueue.sync {
                self.peerConnection?.localDescription?.sdp
            }
            guard let updated, !updated.isEmpty else { return }
            try? await self.signaling.sendOffer(sessionId: sessionId, sdp: updated)
            try? await self.flushLocalIceCandidates(sessionId: sessionId)
        }
    }

    private func setupPeerConnection() throws {
        RTCInitializeSSL()
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        factory = RTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)

        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually

        let pcConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        peerConnection = factory?.peerConnection(with: config, constraints: pcConstraints, delegate: self)

        videoSource = factory?.videoSource()
        let capturer = FramePusher(delegate: videoSource!)
        videoCapturer = capturer

        guard let videoSource, let pc = peerConnection else {
            throw CastError.notConfigured
        }
        videoSource.adaptOutputFormat(
            toWidth: Int32(streamConfig.width),
            height: Int32(streamConfig.height),
            fps: Int32(streamConfig.fps)
        )

        let videoTrack = factory?.videoTrack(with: videoSource, trackId: "screen0")
        guard let videoTrack else {
            throw CastError.notConfigured
        }
        videoTrack.isEnabled = true
        let transceiverInit = RTCRtpTransceiverInit()
        transceiverInit.direction = .sendOnly
        transceiverInit.streamIds = ["screen-stream"]
        pc.addTransceiver(with: videoTrack, init: transceiverInit)

        DispatchQueue.main.async { [weak self] in
            self?.onCaptureReady?()
        }
    }

    private func flushLocalIceCandidates(sessionId: String) async throws {
        let pending = factoryQueue.sync { localIceCandidates }
        for candidate in pending where !candidate.candidate.isEmpty {
            try await signaling.sendIceCandidate(sessionId: sessionId, candidate: candidate)
        }
    }

    private func waitForIceGatheringComplete(timeoutSeconds: Double = 10) async {
        let alreadyComplete = factoryQueue.sync {
            peerConnection?.iceGatheringState == .complete
        }
        if alreadyComplete { return }

        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    self.factoryQueue.async {
                        if self.peerConnection?.iceGatheringState == .complete {
                            continuation.resume()
                        } else {
                            self.iceGatheringContinuations.append(continuation)
                        }
                    }
                }
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                return false
            }
            _ = await group.next()
            group.cancelAll()
        }
        factoryQueue.async {
            self.iceGatheringContinuations.removeAll()
        }
    }

    private func startLocalIceRepublish(sessionId: String) {
        iceRepublishTask?.cancel()
        iceRepublishTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let batch = self.factoryQueue.sync { self.localIceCandidates }
                for candidate in batch where !candidate.candidate.isEmpty {
                    try? await self.signaling.sendIceCandidate(sessionId: sessionId, candidate: candidate)
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func startRemoteIcePolling(sessionId: String) {
        icePollTask?.cancel()
        icePollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let remote = try await signaling.pollRemoteIceCandidates(sessionId: sessionId, side: "receiver")
                    for candidate in remote {
                        try await addRemoteCandidate(candidate)
                    }
                    let iceState = self.currentIceConnectionState()
                    if iceState == .connected || iceState == .completed { break }
                } catch {
                    break
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }

    private func currentIceConnectionState() -> RTCIceConnectionState {
        factoryQueue.sync {
            peerConnection?.iceConnectionState ?? .new
        }
    }

    private func exchangeIce(sessionId: String) async throws {
        let answerSdp = try await signaling.pollAnswer(sessionId: sessionId)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            factoryQueue.async { [weak self] in
                guard let self, let pc = self.peerConnection else {
                    continuation.resume(throwing: CastError.notConfigured)
                    return
                }
                let answer = RTCSessionDescription(type: .answer, sdp: answerSdp)
                pc.setRemoteDescription(answer) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }

        // Poll receiver ICE until media path is up (signaling "connected" != ICE connected).
        for _ in 0..<120 {
            let remote = try await signaling.pollRemoteIceCandidates(sessionId: sessionId, side: "receiver")
            for c in remote {
                try await addRemoteCandidate(c)
            }
            let iceState = currentIceConnectionState()
            if iceState == .connected || iceState == .completed { break }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
    }

    private func addRemoteCandidate(_ candidate: IceCandidate) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            factoryQueue.async { [weak self] in
                guard let pc = self?.peerConnection else {
                    continuation.resume(throwing: CastError.notConfigured)
                    return
                }
                let ice = RTCIceCandidate(
                    sdp: candidate.candidate,
                    sdpMLineIndex: candidate.sdpMLineIndex,
                    sdpMid: candidate.sdpMid
                )
                pc.add(ice) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func frameRotation(from sampleBuffer: CMSampleBuffer) -> RTCVideoRotation {
        if let orientation = CMGetAttachment(
            sampleBuffer,
            key: RPVideoSampleOrientationKey as CFString,
            attachmentModeOut: nil
        ) as? NSNumber {
            switch orientation.uint32Value {
            case 1: return ._0
            case 3: return ._180
            case 6: return ._90
            case 8: return ._270
            default: return ._0
            }
        }
        return ._0
    }
#endif
}

#if canImport(WebRTC)
extension WebRtcBroadcastEngine: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        guard let sessionId = activeSessionId else { return }
        switch newState {
        case .connected, .completed:
            extensionSignalingServer.updateConnectionState(sessionId, state: "connected")
        case .disconnected, .failed, .closed:
            extensionSignalingServer.updateConnectionState(sessionId, state: "disconnected")
            Task {
                try? await signaling.updateSessionStatus(sessionId: sessionId, state: "disconnected")
            }
        default:
            break
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let ice = IceCandidate(
            candidate: candidate.sdp,
            sdpMid: candidate.sdpMid,
            sdpMLineIndex: candidate.sdpMLineIndex
        )
        factoryQueue.async { [weak self] in
            guard let self else { return }
            self.localIceCandidates.append(ice)
            guard self.offerSent, let sessionId = self.activeSessionId, !ice.candidate.isEmpty else { return }
            Task {
                try? await self.signaling.sendIceCandidate(sessionId: sessionId, candidate: ice)
            }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        if newState == .complete {
            factoryQueue.async { [weak self] in
                guard let self else { return }
                let pending = self.iceGatheringContinuations
                self.iceGatheringContinuations.removeAll()
                pending.forEach { $0.resume() }
            }
        }
    }
}
#endif

// ReplayKit orientation key (available without import in extension)
private let RPVideoSampleOrientationKey = "RPVideoSampleOrientationKey"
