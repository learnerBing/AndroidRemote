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
    private let factoryQueue = DispatchQueue(label: "com.androidremote.webrtc")
#endif

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

#if canImport(WebRTC)
        try await startWebRtc(sessionId: session.sessionId)
#else
        throw CastError.webRtcUnavailable
#endif
    }

    func stop() {
        extensionSignalingServer.stop()
        activeSessionId = nil
#if canImport(WebRTC)
        factoryQueue.sync {
            peerConnection?.close()
            peerConnection = nil
            videoSource = nil
            videoCapturer = nil
            factory = nil
            localIceCandidates.removeAll()
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
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            factoryQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CastError.notConfigured)
                    return
                }
                do {
                    try self.setupPeerConnection()
                    guard let pc = self.peerConnection else {
                        throw CastError.notConfigured
                    }

                    let constraints = RTCMediaConstraints(
                        mandatoryConstraints: [
                            "OfferToReceiveAudio": "false",
                            "OfferToReceiveVideo": "false"
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
                        pc.setLocalDescription(sdp) { error in
                            if let error {
                                continuation.resume(throwing: error)
                                return
                            }
                            Task {
                                do {
                                    try await self.signaling.sendOffer(sessionId: sessionId, sdp: sdp.sdp)
                                    try await self.exchangeIce(sessionId: sessionId)
                                    continuation.resume()
                                } catch {
                                    continuation.resume(throwing: error)
                                }
                            }
                        }
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
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

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        peerConnection = factory?.peerConnection(with: config, constraints: constraints, delegate: self)

        videoSource = factory?.videoSource()
        let capturer = FramePusher(delegate: videoSource!)
        videoCapturer = capturer
        let videoTrack = factory?.videoTrack(with: videoSource!, trackId: "screen0")
        if let videoTrack {
            peerConnection?.add(videoTrack, streamIds: ["screen"])
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

        // Send locally gathered ICE candidates
        for candidate in localIceCandidates {
            try await signaling.sendIceCandidate(sessionId: sessionId, candidate: candidate)
        }

        // Poll TV ICE candidates
        for _ in 0..<30 {
            let remote = try await signaling.pollRemoteIceCandidates(sessionId: sessionId)
            for c in remote {
                try await addRemoteCandidate(c)
            }
            let status = try await signaling.pollStatus(sessionId: sessionId)
            if status == "connected" { break }
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
        default:
            break
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        localIceCandidates.append(
            IceCandidate(
                candidate: candidate.sdp,
                sdpMid: candidate.sdpMid,
                sdpMLineIndex: candidate.sdpMLineIndex
            )
        )
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
}
#endif

// ReplayKit orientation key (available without import in extension)
private let RPVideoSampleOrientationKey = "RPVideoSampleOrientationKey"
